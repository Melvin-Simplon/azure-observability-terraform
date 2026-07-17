import time
import logging
import os
from flask import Flask, jsonify

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)


@app.route("/")
def index():
    app.logger.info("Page d'accueil consultée")
    return jsonify({"message": "Hello from App Service 🚀", "owner": os.getenv("OWNER", "unknown")})


@app.route("/health")
def health():
    return jsonify({"status": "ok"}), 200


@app.route("/error")
def error():
    app.logger.error("Erreur 500 déclenchée intentionnellement")
    return jsonify({"error": "Something went wrong"}), 500


@app.route("/slow")
def slow():
    app.logger.warning("Requête lente déclenchée (3s)")
    time.sleep(3)
    return jsonify({"message": "Réponse lente", "delay_seconds": 3}), 200


@app.route("/crash")
def crash():
    app.logger.critical("CRASH simulé")
    raise RuntimeError("Simulation de crash applicatif")


if __name__ == "__main__":
    port = int(os.getenv("PORT", 8000))
    app.run(host="0.0.0.0", port=port)
