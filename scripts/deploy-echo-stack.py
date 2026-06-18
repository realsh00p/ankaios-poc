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

DEFAULT_API = "http://127.0.0.1:8082/v1alpha2"


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


def walk(value):
    yield value
    if isinstance(value, dict):
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def embedded_solution_versions(campaign_version):
    versions = {}
    for value in walk(campaign_version):
        if not isinstance(value, dict):
            continue
        solution_version = value.get("solutionversion")
        if not isinstance(solution_version, dict):
            continue
        name = solution_version.get("metadata", {}).get("name")
        if name:
            versions[name] = solution_version
    return versions


def campaign_resource(campaign_version, campaign_file):
    sibling = campaign_file.with_name("campaign.json")
    if sibling.exists():
        return load_json(sibling)

    root = campaign_version.get("spec", {}).get("rootResource")
    if not root:
        raise SystemExit(f"{campaign_file} has no spec.rootResource and no sibling campaign.json")
    namespace = campaign_version.get("metadata", {}).get("namespace", "default")
    return {"metadata": {"name": root, "namespace": namespace}, "spec": {}}


def campaign_version_ref(campaign_version):
    root = campaign_version.get("spec", {}).get("rootResource")
    name = campaign_version.get("metadata", {}).get("name")
    if not root or not name:
        raise SystemExit("Campaign version needs metadata.name and spec.rootResource")

    prefix = f"{root}-v-"
    if not name.startswith(prefix):
        raise SystemExit(f"Cannot derive campaign version ref: {name} does not start with {prefix}")
    return f"{root}:{name[len(prefix):]}"


def candidate_instance_name(campaign_version):
    stages = campaign_version.get("spec", {}).get("stages", {})
    deploy = stages.get("deploy-candidate", {})
    return (
        deploy.get("inputs", {})
        .get("body", {})
        .get("metadata", {})
        .get("name")
    )


def run_text(command):
    return subprocess.check_output(command, text=True, timeout=15, stderr=subprocess.DEVNULL)


def echo_client_40102_command_args():
    try:
        output = run_text(["ank", "-k", "get", "state"])
    except (subprocess.SubprocessError, FileNotFoundError):
        return ""

    show = False
    for line in output.splitlines():
        if "echo-client-40102:" in line:
            show = True
        elif show and "commandArgs:" in line:
            return line.strip()
    return ""


def seed_campaign(api, campaign_file):
    campaign_version = load_json(campaign_file)
    campaign = campaign_resource(campaign_version, campaign_file)
    campaign_name = campaign["metadata"]["name"]
    campaign_version_name = campaign_version["metadata"]["name"]

    post_resource(api, f"campaigns/{campaign_name}", campaign)
    for name, solution_version in embedded_solution_versions(campaign_version).items():
        post_resource(api, f"solutionversions/{name}", solution_version)
    post_resource(api, f"campaignversions/{campaign_version_name}", campaign_version)
    return campaign_version


def start_activation(api, campaign_ref, activation_name=None):
    activation = activation_name or f"echo-stack-update-{time.strftime('%Y%m%d%H%M%S')}"
    payload = {
        "metadata": {"name": activation, "namespace": "default"},
        "spec": {"campaignversion": campaign_ref},
    }
    print(f"Starting Symphony activation: {activation}")
    print(f"campaignversion={campaign_ref}")
    post_resource(api, f"activations/registry/{activation}", payload)
    return activation


def wait_for_activation_done(api, activation, instance_name=None, timeout=180):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        status = get_resource(api, f"activations/registry/{activation}")
        state = status.get("status", {})
        message = state.get("statusMessage") or state.get("properties", {}).get("statusMessage", "")

        details = []
        if instance_name:
            _, instance = request_json("GET", f"{api.rstrip(chr(47))}/instances/{instance_name}", fail_on_http_error=False)
            if isinstance(instance, dict) and "spec" in instance:
                current_version = instance.get("spec", {}).get("solutionversion", "")
                details.append(f"instance={current_version}")
            else:
                details.append("instance=<missing>")
        command_args = echo_client_40102_command_args()
        if command_args:
            details.append(command_args)
        print(f"activation={message} {' '.join(details)}".rstrip())

        if message == "Done":
            history = state.get("stageHistory") or state.get("properties", {}).get("stageHistory")
            if history:
                print(json.dumps(history, indent=2, sort_keys=True))
            return
        if "Error" in message:
            print(json.dumps(status, indent=2, sort_keys=True), file=sys.stderr)
            raise SystemExit(f"Activation failed: {message}")
        time.sleep(5)
    raise SystemExit(f"Timed out waiting for Symphony activation {activation}")


def main():
    parser = argparse.ArgumentParser(description="Deploy and validate a Symphony campaign version")
    parser.add_argument("campaign_file", type=Path, help="Path to a campaign version JSON file")
    parser.add_argument("--api", default=os.environ.get("SYMPHONY_API", DEFAULT_API))
    parser.add_argument("--campaign-version", help="Override the campaign version ref, for example name:v2-good")
    parser.add_argument("--activation-name")
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()

    campaign_file = args.campaign_file
    if not campaign_file.exists():
        raise SystemExit(f"Campaign file does not exist: {campaign_file}")

    print(f"Seeding Symphony campaign from {campaign_file}")
    campaign_version = seed_campaign(args.api, campaign_file)
    campaign_ref = args.campaign_version or campaign_version_ref(campaign_version)
    activation = start_activation(args.api, campaign_ref, args.activation_name)
    wait_for_activation_done(args.api, activation, candidate_instance_name(campaign_version), args.timeout)


if __name__ == "__main__":
    main()
