"""Called by the Swift HTTP contract XCTest. Its server uses stub services, never broker jobs."""
import argparse
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
SPEC = importlib.util.spec_from_file_location("pir", Path(__file__).resolve().parents[1] / "pir.py")
pir = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pir)


def expect_http(client, status, method, path, body=None):
    try:
        client.request(method, path, body)
    except pir.Failed as error:
        assert f"HTTP {status};" in str(error), str(error)
    else:
        raise AssertionError(f"expected HTTP {status} for {method} {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--instance", required=True)
    parser.add_argument("--evidence-dir", type=Path, required=True)
    args = parser.parse_args()
    token = "contract-test-credential"
    client = pir.Client(args.evidence_dir, args.port, args.instance, pir.Redactor(token))
    snapshot = client.prerequisite(timeout=10)
    assert snapshot["result"]["status"] == "credentialProvided", snapshot
    assert snapshot["result"]["entitled"] is None, snapshot
    logs = client.request("GET", "/api/logs?limit=1")
    assert client.last_status == 200 and len(logs) == 1, logs
    assert logs[0]["message"] == f"log canary {token}", logs
    assert set(logs[0]) == {"timestamp", "level", "category", "subsystem", "process", "message"}, logs

    scan = dict(broker=dict(name="Contract", url="https://broker.invalid", version="1", steps=[]),
                profile=dict(names=[dict(firstName="Contract", lastName="Person")],
                             addresses=[dict(city="Test", state="CA")], phones=[], birthYear=1980), hidesWebView=True)
    foreign_evidence = args.evidence_dir / "foreign"
    foreign_evidence.mkdir()
    foreign = pir.Client(foreign_evidence, args.port, "wrong-instance", pir.Redactor(token))
    foreign.owned = True
    expect_http(foreign, 403, "POST", "/api/debug/scans", scan)
    client.opener.addheaders.append(("Origin", "https://page.invalid"))
    expect_http(client, 403, "POST", "/api/debug/scans", scan)
    client.opener.addheaders = [(key, value) for key, value in client.opener.addheaders if key != "Origin"]
    expect_http(client, 400, "GET", "/api/debug/prerequisites?checkID=invalid")
    expect_http(client, 400, "POST", "/api/debug/scans", {})
    expect_http(client, 404, "GET", "/api/debug/runs/missing")

    run = client.request("POST", "/api/debug/scans", scan)
    assert client.last_status == 202 and run["id"] == "contract-run" and run["activity"] == "scan", run
    run = client.idle(run["id"], 5)
    assert len(run["results"]) == 1 and run["results"][0]["id"] == "record", run
    path = "/api/debug/runs/contract-run"
    expect_http(foreign, 403, "POST", f"{path}/optouts/record")
    opted = client.request("POST", f"{path}/optouts/record")
    assert client.last_status == 202 and opted["results"][0]["optOutStatus"] == "awaitingEmailConfirmation", opted
    email = client.request("POST", f"{path}/email-confirmation/check")
    assert client.last_status == 202 and email["results"][0]["hasEmailConfirmationLink"] is True, email
    confirmed = client.request("POST", f"{path}/optouts/record/continue")
    assert client.last_status == 202 and confirmed["results"][0]["optOutStatus"] == "confirmed", confirmed
    confirmed = client.idle("contract-run", 5)
    assert confirmed["results"][0]["optOutStatus"] == "confirmed"
    assert pir.selected(confirmed, profile_url="https://record.invalid")["id"] == "record"
    for failed_run in ("scan-error-run", "opt-out-error-run", "opt-out-failed-run", "error-event-run", "email-failure-run"):
        try:
            client.idle(failed_run, 5)
        except pir.Failed as error:
            assert "PIR run contains" in str(error), str(error)
        else:
            raise AssertionError(f"{failed_run} was accepted as a clean run")
    records = [json.loads(path.read_text()) for path in args.evidence_dir.glob("pir-http-*.json")]
    saved_logs = [record for record in records if record["path"] == "/api/logs?limit=1"]
    assert saved_logs[0]["response"][0]["message"] == "log canary [REDACTED]", saved_logs
    assert all(token not in json.dumps(record) for record in records)
    print("Swift HTTP/Python client contract passed; only stub run services were called.")


if __name__ == "__main__":
    main()
