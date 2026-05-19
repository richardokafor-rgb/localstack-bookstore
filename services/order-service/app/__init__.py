from decimal import Decimal

from flask import Flask
from flask.json.provider import DefaultJSONProvider
from flask_cors import CORS


class DecimalJSONProvider(DefaultJSONProvider):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super().default(obj)


def create_app():
    app = Flask(__name__)
    app.json_provider_class = DecimalJSONProvider
    app.json = DecimalJSONProvider(app)
    CORS(app)

    from .routes import bp
    app.register_blueprint(bp)

    return app
