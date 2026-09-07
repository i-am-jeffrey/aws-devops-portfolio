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
    # nosemgrep: python.flask.security.audit.app-run-param-config.avoid_app_run_with_bad_host
    # This rule is correct in general (binding a dev server to all interfaces
    # is a real anti-pattern), but wrong for this specific case: this process
    # runs inside a container, where 0.0.0.0 is required, not risky -- binding
    # to 127.0.0.1 here would make the app unreachable from the Kubernetes
    # Service routing to it.
    app.run(host="0.0.0.0", port=8080)
