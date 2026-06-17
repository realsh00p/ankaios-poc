#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(line_buffering=True)
from http.client import RemoteDisconnected
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
ECHO_STACK = ROOT / "symphony" / "ankaios" / "echo-stack"
TARGET_FILE = ROOT / "symphony" / "ankaios" / "target" / "linaro-ankaios.json"
CAMPAIGN_DIR = ROOT / "symphony" / "campaigns" / "echo-stack-validation"
DEFAULT_API = "http://127.0.0.1:8082/v1alpha2"
ECHO_CLIENT_40102_HEALTH = "http://192.168.10.240:41102/health"

VARIANTS = {
    "good": {
        "solution_version": ECHO_STACK / "solution-version.json",
        "instance": ECHO_STACK / "instance.json",
        "solution_version_id": "ankaios-echo-stack-v-v1",
    },
    "bad-client": {
        "solution_version": ECHO_STACK / "solution-version-bad-client.json",
        "instance": ECHO_STACK / "instance-bad-client.json",
        "solution_version_id": "ankaios-echo-stack-v-v2-bad-client",
    },
}


def load_json(path):
    with path.open() as f:
        return json.load(f)


def request_json(method, url, payload=None, timeout=60, fail_on_http_error=True):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = Request(url, data=data, method=method, headers={"Content-Type": "application/json"})
    try:
        with urlopen(req, timeout=timeout) as response:
            body = response.read().decode("utf-8", "replace")
            return response.status, json.loads(body) if body else None
    except HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        payload = None
        if body:
            try:
                payload = json.loads(body)
            except json.JSONDecodeError:
                payload = {"body": body}
        if fail_on_http_error:
            raise SystemExit(f"{method} {url} failed with HTTP {exc.code}: {body}") from exc
        return exc.code, payload
    except (ConnectionError, RemoteDisconnected, TimeoutError, URLError) as exc:
        if fail_on_http_error:
            raise SystemExit(f"{method} {url} failed: {exc}") from exc
        return 0, {"error": str(exc)}


def post_resource(api, path, payload):
    _, result = request_json("POST", f"{api.rstrip('/')}/{path.lstrip('/')}", payload)
    return result


def get_resource(api, path):
    _, result = request_json("GET", f"{api.rstrip('/')}/{path.lstrip('/')}")
    return result


def deployment_spec(solution_version, instance, target):
    target_name = target["metadata"]["name"]
    components = solution_version["spec"]["components"]
    return {
        "solutionversionName": solution_version["metadata"]["name"],
        "solutionversion": solution_version,
        "instance": instance,
        "targets": {target_name: target},
        "assignments": {target_name: "".join("{" + c["name"] + "}" for c in components)},
        "objectNamespace": instance.get("metadata", {}).get("namespace", "default"),
        "generation": instance.get("metadata", {}).get("etag", ""),
        "isDryRun": False,
        "isInActive": False,
    }


def seed_validation_campaign(api):
    post_resource(api, "campaigns/ankaios-echo-stack-validation", load_json(CAMPAIGN_DIR / "campaign.json"))
    post_resource(api, "campaignversions/ankaios-echo-stack-validation-v-v1", load_json(CAMPAIGN_DIR / "campaign-version.json"))


def reconcile(api, variant_name, output=True):
    variant = VARIANTS[variant_name]
    target = load_json(TARGET_FILE)
    solution_version = load_json(variant["solution_version"])
    instance = load_json(variant["instance"])
    namespace = instance.get("metadata", {}).get("namespace", "default")

    post_resource(api, f"targets/registry/{target['metadata']['name']}", target)
    post_resource(api, f"solutionversions/{variant['solution_version_id']}", solution_version)
    post_resource(api, f"instances/{instance['metadata']['name']}", instance)

    summary = post_resource(
        api,
        f"solutionversion/reconcile?namespace={namespace}",
        deployment_spec(solution_version, instance, target),
    )
    if output:
        json.dump(summary, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
    if not summary or not summary.get("allAssignedDeployed"):
        raise SystemExit(1)
    return summary


def run_text(command):
    return subprocess.check_output(command, text=True, timeout=15)


def echo_client_40102_state():
    output = run_text(["ank", "-k", "get", "workloads"])
    for line in output.splitlines():
        parts = line.split()
        if parts and parts[0] == "echo-client-40102":
            return " ".join(parts[3:])
    return "missing"


def echo_client_40102_command_args():
    output = run_text(["ank", "-k", "get", "state"])
    show = False
    for line in output.splitlines():
        if "echo-client-40102:" in line:
            show = True
        elif show and "commandArgs:" in line:
            return line.strip()
    return "commandArgs: <missing>"


def client_health(fail_on_http_error=False):
    return request_json("GET", ECHO_CLIENT_40102_HEALTH, timeout=20, fail_on_http_error=fail_on_http_error)


def wait_for_unhealthy_client(timeout=120):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        state = echo_client_40102_state()
        code, payload = client_health(fail_on_http_error=False)
        reason = payload.get("reason") if isinstance(payload, dict) else None
        endpoint = payload.get("endpoint") if isinstance(payload, dict) else None
        print(f"echo-client-40102={state} health={code} endpoint={endpoint} reason={reason}")
        if code == 503:
            return
        time.sleep(5)
    raise SystemExit("Timed out waiting for echo-client-40102 container health to become unhealthy")


def ensure_client_health_fails():
    code, payload = client_health(fail_on_http_error=False)
    if code != 503:
        raise SystemExit(f"Expected echo-client-40102 health to return 503 before validation, got {code}")
    print("Container health endpoint is unhealthy as expected:")
    if isinstance(payload, dict):
        for value in (payload.get("endpoint"), payload.get("reason")):
            if value:
                print(value)


def start_validation_activation(api):
    activation = f"echo-stack-bad-port-{time.strftime('%Y%m%d%H%M%S')}"
    payload = {
        "metadata": {"name": activation, "namespace": "default"},
        "spec": {"campaignversion": "ankaios-echo-stack-validation:v1"},
    }
    print(f"Starting Symphony validation activation: {activation}")
    post_resource(api, f"activations/registry/{activation}", payload)
    return activation


def wait_for_activation_done(api, activation, timeout=180):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        status = get_resource(api, f"activations/registry/{activation}")
        message = status.get("status", {}).get("statusMessage") or status.get("status", {}).get("properties", {}).get("statusMessage", "")
        instance = get_resource(api, "instances/ankaios-echo-stack-instance")
        current_version = instance.get("spec", {}).get("solutionversion", "")
        print(f"activation={message} instance={current_version} {echo_client_40102_command_args()}")
        if message == "Done":
            history = status.get("status", {}).get("stageHistory") or status.get("status", {}).get("properties", {}).get("stageHistory")
            print(json.dumps(history, indent=2, sort_keys=True))
            return
        if "Error" in message:
            print(json.dumps(status, indent=2, sort_keys=True), file=sys.stderr)
            raise SystemExit(f"Activation failed: {message}")
        time.sleep(5)
    raise SystemExit(f"Timed out waiting for Symphony activation {activation}")


def wait_for_recovered_client(api, timeout=90):
    instance = get_resource(api, "instances/ankaios-echo-stack-instance")
    current_version = instance.get("spec", {}).get("solutionversion", "")
    if current_version != "ankaios-echo-stack:v1":
        raise SystemExit(f"Rollback failed: Symphony instance is {current_version}")

    print("Waiting for echo-client-40102 to become healthy after rollback")
    deadline = time.monotonic() + timeout
    last_payload = None
    while time.monotonic() < deadline:
        code, payload = client_health(fail_on_http_error=False)
        last_payload = payload
        if code == 200:
            print("Rollback verified: Symphony instance is ankaios-echo-stack:v1 and echo-client-40102 is healthy again")
            return
        if payload:
            for value in (payload.get("endpoint"), payload.get("reason")):
                if value:
                    print(value)
        time.sleep(5)
    raise SystemExit(f"Rollback failed: echo-client-40102 health is still failing: {json.dumps(last_payload, sort_keys=True)}")


def run_bad_client_rollback_test(api):
    print(f"Seeding Symphony resources into {api}")
    seed_validation_campaign(api)
    print("Deploying bad echo stack: echo-client-40102 -> http://192.168.10.240:40999")
    reconcile(api, "bad-client", output=False)
    print("Waiting for echo-client-40102 container health to report unhealthy")
    wait_for_unhealthy_client()
    ensure_client_health_fails()
    activation = start_validation_activation(api)
    wait_for_activation_done(api, activation)
    wait_for_recovered_client(api)


def main():
    parser = argparse.ArgumentParser(description="Deploy and validate the Symphony Ankaios echo stack")
    parser.add_argument("variant", choices=["good", "bad-client", "bad-client-with-rollback-test"])
    parser.add_argument("--api", default=os.environ.get("SYMPHONY_API", DEFAULT_API))
    args = parser.parse_args()

    if args.variant == "bad-client-with-rollback-test":
        run_bad_client_rollback_test(args.api)
    else:
        reconcile(args.api, args.variant)


if __name__ == "__main__":
    main()
