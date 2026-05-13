const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  UpdateCommand,
  DeleteCommand,
  ScanCommand,
  QueryCommand,
} = require("@aws-sdk/lib-dynamodb");
const { randomUUID } = require("crypto");

const client = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(client);
const TABLE = process.env.BOOKS_TABLE;

const response = (statusCode, body) => ({
  statusCode,
  headers: {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
  },
  body: JSON.stringify(body),
});

async function listBooks(event) {
  const { genre } = event.queryStringParameters || {};
  if (genre) {
    const result = await ddb.send(
      new QueryCommand({
        TableName: TABLE,
        IndexName: "genre-index",
        KeyConditionExpression: "genre = :g",
        ExpressionAttributeValues: { ":g": genre },
      })
    );
    return response(200, result.Items);
  }
  const result = await ddb.send(new ScanCommand({ TableName: TABLE }));
  return response(200, result.Items);
}

async function getBook(bookId) {
  const result = await ddb.send(
    new GetCommand({ TableName: TABLE, Key: { bookId } })
  );
  if (!result.Item) return response(404, { message: "Book not found" });
  return response(200, result.Item);
}

async function createBook(body) {
  const data = JSON.parse(body || "{}");
  const required = ["title", "author", "genre", "price"];
  for (const field of required) {
    if (!data[field])
      return response(400, { message: `Missing required field: ${field}` });
  }
  const item = {
    bookId: randomUUID(),
    ...data,
    stock: data.stock ?? 0,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
  await ddb.send(new PutCommand({ TableName: TABLE, Item: item }));
  return response(201, item);
}

async function updateBook(bookId, body) {
  const data = JSON.parse(body || "{}");
  const fields = Object.keys(data);
  if (!fields.length) return response(400, { message: "No fields to update" });

  const updateExpr =
    "SET " +
    fields.map((f, i) => `#f${i} = :v${i}`).join(", ") +
    ", updatedAt = :ts";
  const names = Object.fromEntries(fields.map((f, i) => [`#f${i}`, f]));
  const values = Object.fromEntries(fields.map((f, i) => [`:v${i}`, data[f]]));
  values[":ts"] = new Date().toISOString();

  const result = await ddb.send(
    new UpdateCommand({
      TableName: TABLE,
      Key: { bookId },
      UpdateExpression: updateExpr,
      ExpressionAttributeNames: names,
      ExpressionAttributeValues: values,
      ConditionExpression: "attribute_exists(bookId)",
      ReturnValues: "ALL_NEW",
    })
  );
  return response(200, result.Attributes);
}

async function deleteBook(bookId) {
  await ddb.send(
    new DeleteCommand({
      TableName: TABLE,
      Key: { bookId },
      ConditionExpression: "attribute_exists(bookId)",
    })
  );
  return response(204, {});
}

exports.handler = async (event) => {
  try {
    const method = event.requestContext.http.method;
    const bookId = event.pathParameters?.bookId;

    if (method === "GET" && !bookId) return listBooks(event);
    if (method === "GET" && bookId) return getBook(bookId);
    if (method === "POST") return createBook(event.body);
    if (method === "PUT" && bookId) return updateBook(bookId, event.body);
    if (method === "DELETE" && bookId) return deleteBook(bookId);

    return response(405, { message: "Method not allowed" });
  } catch (err) {
    if (err.name === "ConditionalCheckFailedException")
      return response(404, { message: "Book not found" });
    console.error(err);
    return response(500, { message: "Internal server error" });
  }
};
