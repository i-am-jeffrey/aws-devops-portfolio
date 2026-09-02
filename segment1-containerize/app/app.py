from flask import Flask, jsonify

app = Flask(__name__)


@app.route("/")
def hello():
    return jsonify(message="Hello from the Segment 1 placeholder app", status="ok")


@app.route("/healthz")
def healthz():
    # Used by Kubernetes readiness/liveness probes -- keep this cheap and dependency-free
    return jsonify(status="healthy"), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
