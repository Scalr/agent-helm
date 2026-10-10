"""Render and validate agent-local's public workload/storage contract.

Run with: just test
Requires Helm on PATH and uv. No cluster or agent credentials are used.
"""

import itertools
import json
import os
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any
from typing import Literal

import pytest
import yaml

CHART = Path(__file__).resolve().parents[1] / "charts" / "agent-local"
HELM = os.environ.get("HELM_BIN", "helm")
NAME = "storage-test-agent-local"
MODES = ("emptyDir", "persistentVolumeClaim", "ephemeral", "volumeClaimTemplate")


def run_helm(
    command: Literal["template", "lint"],
    values: dict[str, Any] | None = None,
    chart: Path = CHART,
    *,
    release_name: str = "storage-test",
    is_upgrade: bool = False,
) -> subprocess.CompletedProcess[str]:
    """Run Helm locally with supplied values and a dummy agent token."""
    # JSON is valid YAML, and stdin avoids shell interpolation and temporary files.
    args = [HELM, command]
    if command == "template":
        args += [
            release_name,
            str(chart),
            "--namespace",
            "chart-tests",
            "--kube-version",
            "1.33.0",
        ]
        if is_upgrade:
            args.append("--is-upgrade")
    else:
        args += [str(chart)]
    return subprocess.run(
        [*args, "--set", "agent.token=dummy", "-f", "-"],
        input=json.dumps(values or {}),
        capture_output=True,
        text=True,
        check=False,
    )


def render(
    values: dict[str, Any] | None = None,
    chart: Path = CHART,
    *,
    release_name: str = "storage-test",
    is_upgrade: bool = False,
) -> list[dict[str, Any]]:
    """Require a successful render and return its nonempty YAML documents."""
    result = run_helm("template", values, chart, release_name=release_name, is_upgrade=is_upgrade)
    assert result.returncode == 0, result.stdout + result.stderr
    return [doc for doc in yaml.safe_load_all(result.stdout) if doc]


def resource(docs: list[dict[str, Any]], kind: str) -> dict[str, Any]:
    """Return the first rendered resource of the requested kind."""
    return next(doc for doc in docs if doc["kind"] == kind)


def volumes(workload: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """Index explicit pod volumes by name."""
    return {
        volume["name"]: volume for volume in workload["spec"]["template"]["spec"].get("volumes", [])
    }


def assert_invalid(values: dict[str, Any], message: str, chart: Path = CHART) -> None:
    """Require rendering and linting to reject values and identify the invalid setting."""
    for command in ("template", "lint"):
        result = run_helm(command, values, chart)
        output = result.stdout + result.stderr
        assert result.returncode != 0, f"helm {command} accepted invalid values: {values}\n{output}"
        assert message in output, f"helm {command} did not identify {message}:\n{output}"


@pytest.mark.parametrize(
    "values",
    [{}, {"workload": None}, {"workload": {"kind": None}}],
    ids=("default", "unset-workload", "unset-kind"),
)
def test_default_deployment_contract(values: dict[str, Any]) -> None:
    """Default values retain the original Deployment and emptyDir layout."""
    docs = render(values)
    deployment = resource(docs, "Deployment")
    assert deployment["metadata"]["name"] == NAME
    assert deployment["spec"]["replicas"] == 1
    assert deployment["spec"]["strategy"] == {
        "type": "RollingUpdate",
        "rollingUpdate": {"maxSurge": "25%", "maxUnavailable": "50%"},
    }
    assert volumes(deployment) == {
        "data-dir": {"name": "data-dir", "emptyDir": {"sizeLimit": "4Gi"}},
        "cache-dir": {"name": "cache-dir", "emptyDir": {"sizeLimit": "20Gi"}},
    }
    assert not any(
        doc["kind"] in ("StatefulSet", "PersistentVolumeClaim", "Service") for doc in docs
    )


@pytest.mark.parametrize(
    "kind,data_mode,cache_mode",
    [
        (kind, data_mode, cache_mode)
        for kind in ("Deployment", "StatefulSet")
        for data_mode, cache_mode in itertools.product(
            MODES if kind == "StatefulSet" else MODES[:-1], repeat=2
        )
    ],
)
def test_all_supported_storage_combinations(kind: str, data_mode: str, cache_mode: str) -> None:
    """Data and cache modes resolve independently for each supported controller."""
    docs = render(
        {
            "workload": {"kind": kind},
            "replicaCount": 3,
            "persistence": {"data": {"mode": data_mode}, "cache": {"mode": cache_mode}},
        }
    )
    workload = resource(docs, kind)
    pod = workload["spec"]["template"]["spec"]
    actual_volumes = volumes(workload)
    templates = {
        claim["metadata"]["name"]: claim
        for claim in workload["spec"].get("volumeClaimTemplates", [])
    }
    claims = {
        doc["metadata"]["name"]: doc for doc in docs if doc["kind"] == "PersistentVolumeClaim"
    }
    assert workload["spec"]["replicas"] == 3
    assert {mount["name"] for mount in pod["containers"][0]["volumeMounts"]} == {
        "data-dir",
        "cache-dir",
    }
    assert set(claims) == {
        NAME + "-" + name
        for name, mode in (("data", data_mode), ("cache", cache_mode))
        if mode == "persistentVolumeClaim"
    }
    assert set(templates) == {
        name + "-dir"
        for name, mode in (("data", data_mode), ("cache", cache_mode))
        if mode == "volumeClaimTemplate"
    }
    for name, mode in [("data", data_mode), ("cache", cache_mode)]:
        volume_name = name + "-dir"
        if mode == "volumeClaimTemplate":
            assert volume_name not in actual_volumes
            assert volume_name in templates
            claim_spec = templates[volume_name]["spec"]
        elif mode == "ephemeral":
            assert set(actual_volumes[volume_name]) == {"name", "ephemeral"}
            claim_spec = actual_volumes[volume_name]["ephemeral"]["volumeClaimTemplate"]["spec"]
        elif mode == "persistentVolumeClaim":
            claim_name = NAME + "-" + name
            assert actual_volumes[volume_name]["persistentVolumeClaim"]["claimName"] == claim_name
            claim_spec = claims[claim_name]["spec"]
        else:
            assert actual_volumes[volume_name]["emptyDir"]["sizeLimit"] == (
                "4Gi" if name == "data" else "20Gi"
            )
            continue
        assert claim_spec["accessModes"] == ["ReadWriteOnce"]
        assert claim_spec["resources"]["requests"]["storage"] == (
            "4Gi" if name == "data" else "20Gi"
        )
        assert "storageClassName" not in claim_spec
    if kind == "StatefulSet":
        service = resource(docs, "Service")
        assert service["spec"]["clusterIP"] == "None"
        assert service["metadata"]["name"] == workload["spec"]["serviceName"]
        assert service["spec"]["selector"] == workload["spec"]["selector"]["matchLabels"]
        assert "strategy" not in workload["spec"]
        assert workload["spec"]["podManagementPolicy"] == "Parallel"
        if templates:
            assert workload["spec"]["persistentVolumeClaimRetentionPolicy"] == {
                "whenDeleted": "Retain",
                "whenScaled": "Retain",
            }
        else:
            assert "persistentVolumeClaimRetentionPolicy" not in workload["spec"]
    else:
        assert "updateStrategy" not in workload["spec"]
        assert not any(doc["kind"] == "Service" for doc in docs)


@pytest.mark.parametrize("storage_class", ("", "-", "fast-disks"))
@pytest.mark.parametrize(
    "kind,mode",
    [
        (kind, mode)
        for kind, mode in itertools.product(("Deployment", "StatefulSet"), MODES[1:])
        if kind == "StatefulSet" or mode != "volumeClaimTemplate"
    ],
)
def test_claim_settings_and_subpaths(kind: str, mode: str, storage_class: str) -> None:
    """All PVC modes honor claim settings and mount subpaths."""
    docs = render(
        {
            "workload": {"kind": kind},
            "persistence": {
                "cache": {
                    "mode": mode,
                    "persistentVolumeClaim": {
                        "storage": "42Gi",
                        "storageClassName": storage_class,
                        "accessMode": "ReadWriteOncePod",
                        "subPath": "providers",
                        "annotations": {
                            "example.com/owner": "agents",
                            "helm.sh/resource-policy": "keep",
                        },
                    },
                }
            },
        }
    )
    workload = resource(docs, kind)
    if mode == "persistentVolumeClaim":
        claim = resource(docs, "PersistentVolumeClaim")
    elif mode == "ephemeral":
        claim = volumes(workload)["cache-dir"]["ephemeral"]["volumeClaimTemplate"]
    else:
        claim = workload["spec"]["volumeClaimTemplates"][0]
    expected_annotations = {"example.com/owner": "agents"}
    if mode == "persistentVolumeClaim":
        expected_annotations["helm.sh/resource-policy"] = "keep"
    assert claim["metadata"]["annotations"] == expected_annotations
    assert claim["spec"]["resources"]["requests"]["storage"] == "42Gi"
    assert claim["spec"]["accessModes"] == ["ReadWriteOncePod"]
    if storage_class:
        assert claim["spec"]["storageClassName"] == ("" if storage_class == "-" else storage_class)
    else:
        assert "storageClassName" not in claim["spec"]
    mounts = workload["spec"]["template"]["spec"]["containers"][0]["volumeMounts"]
    assert next(m for m in mounts if m["name"] == "cache-dir")["subPath"] == "providers"


@pytest.mark.parametrize("kind", ("Deployment", "StatefulSet"))
def test_existing_claims_work_for_both_controllers(kind: str) -> None:
    """Existing claims are mounted without creating replacements."""
    docs = render(
        {
            "workload": {"kind": kind},
            "persistence": {
                name: {
                    "enabled": True,
                    "persistentVolumeClaim": {"claimName": name + "-existing"},
                }
                for name in ("data", "cache")
            },
        }
    )
    assert not any(doc["kind"] == "PersistentVolumeClaim" for doc in docs)
    assert volumes(resource(docs, kind)) == {
        "data-dir": {"name": "data-dir", "persistentVolumeClaim": {"claimName": "data-existing"}},
        "cache-dir": {
            "name": "cache-dir",
            "persistentVolumeClaim": {"claimName": "cache-existing"},
        },
    }


@pytest.mark.parametrize(
    "claim_name,enabled,modern_enabled,expected_name,expected_storage",
    [
        pytest.param("", True, False, NAME, "7Gi", id="legacy-settings"),
        pytest.param("", False, True, NAME + "-cache", "99Gi", id="modern-settings"),
        pytest.param("legacy-existing", True, False, "legacy-existing", None, id="legacy-claim"),
        pytest.param(
            "legacy-existing",
            False,
            True,
            "legacy-existing",
            None,
            id="legacy-claim-overrides-modern",
        ),
    ],
)
def test_legacy_cache_name_and_precedence(
    claim_name: str,
    enabled: bool,
    modern_enabled: bool,
    expected_name: str,
    expected_storage: str | None,
) -> None:
    """Legacy cache settings retain their claim names and precedence."""
    docs = render(
        {
            "persistence": {
                "enabled": enabled,
                "persistentVolumeClaim": {"claimName": claim_name, "storage": "7Gi"},
                "cache": {
                    "enabled": modern_enabled,
                    "persistentVolumeClaim": {"storage": "99Gi"},
                },
            }
        }
    )
    assert (
        volumes(resource(docs, "Deployment"))["cache-dir"]["persistentVolumeClaim"]["claimName"]
        == expected_name
    )
    if expected_storage is not None:
        assert (
            resource(docs, "PersistentVolumeClaim")["spec"]["resources"]["requests"]["storage"]
            == expected_storage
        )
    else:
        assert not any(doc["kind"] == "PersistentVolumeClaim" for doc in docs)


def test_explicit_mode_overrides_enabled() -> None:
    """An explicit mode takes precedence over the volume's enabled flag."""
    docs = render({"persistence": {"cache": {"enabled": True, "mode": "ephemeral"}}})
    assert "ephemeral" in volumes(resource(docs, "Deployment"))["cache-dir"]
    assert not any(doc["kind"] == "PersistentVolumeClaim" for doc in docs)


@pytest.mark.parametrize(
    "update_strategy",
    [
        pytest.param({"type": "OnDelete"}, id="manual-updates"),
        pytest.param(
            {"type": "RollingUpdate", "rollingUpdate": {"partition": 1}}, id="partitioned-rollout"
        ),
    ],
)
def test_statefulset_controls(update_strategy: dict[str, Any]) -> None:
    """StatefulSet rollout, pod ordering, and retention settings reach the manifest."""
    docs = render(
        {
            "workload": {
                "kind": "StatefulSet",
                "statefulSet": {
                    "podManagementPolicy": "OrderedReady",
                    "updateStrategy": update_strategy,
                    "persistentVolumeClaimRetentionPolicy": {"whenScaled": "Delete"},
                },
            },
            "persistence": {"cache": {"mode": "volumeClaimTemplate"}},
        }
    )
    spec = resource(docs, "StatefulSet")["spec"]
    assert spec["podManagementPolicy"] == "OrderedReady"
    assert spec["updateStrategy"] == update_strategy
    assert spec["persistentVolumeClaimRetentionPolicy"] == {
        "whenDeleted": "Retain",
        "whenScaled": "Delete",
    }


def test_chart_and_app_upgrades_do_not_change_immutable_claim_templates(tmp_path: Path) -> None:
    """Version bumps must not change immutable StatefulSet claim templates."""
    values = {
        "workload": {"kind": "StatefulSet"},
        "persistence": {"cache": {"mode": "volumeClaimTemplate"}},
    }
    original = resource(render(values), "StatefulSet")
    upgraded_chart = tmp_path / "agent-local"
    shutil.copytree(CHART, upgraded_chart)
    metadata_path = upgraded_chart / "Chart.yaml"
    metadata = yaml.safe_load(metadata_path.read_text())
    metadata.update(version="99.0.0", appVersion="99.0.0")
    metadata_path.write_text(yaml.safe_dump(metadata))
    upgraded = resource(render(values, chart=upgraded_chart), "StatefulSet")
    assert original["spec"]["volumeClaimTemplates"] == upgraded["spec"]["volumeClaimTemplates"]
    assert (
        original["spec"]["template"]["spec"]["containers"][0]["image"]
        != upgraded["spec"]["template"]["spec"]["containers"][0]["image"]
    )


def test_shared_pod_configuration_is_preserved() -> None:
    """Both controllers preserve agent, TLS, and custom pod settings."""
    values = {
        "agent": {
            "shutdownMode": "drain",
            "tls": {
                "clientCertSecret": {"name": "client-tls"},
                "caBundleSecret": {"name": "ca-bundle"},
            },
        },
        "podLabels": {"team": "infra", "app.kubernetes.io/name": "cannot-override"},
        "podAnnotations": {
            "example.com/annotation": "present",
            "karpenter.sh/do-not-disrupt": "false",
        },
        "extraEnv": {"EXAMPLE": "value"},
        "extraVolumes": [{"name": "config", "configMap": {"name": "extra-config"}}],
        "extraVolumeMounts": [{"name": "config", "mountPath": "/etc/extra-config"}],
        "persistence": {"data": {"mode": "ephemeral"}, "cache": {"enabled": True}},
    }
    deployment = resource(render(values), "Deployment")
    statefulset = resource(render(dict(values, workload={"kind": "StatefulSet"})), "StatefulSet")
    assert deployment["spec"]["template"] == statefulset["spec"]["template"]
    assert deployment["spec"]["template"]["metadata"]["annotations"] == {
        "cluster-autoscaler.kubernetes.io/safe-to-evict": "false",
        "karpenter.sh/do-not-evict": "true",
        "karpenter.sh/do-not-disrupt": "false",
        "autopilot.gke.io/priority": "high",
        "example.com/annotation": "present",
    }
    assert (
        deployment["spec"]["template"]["metadata"]["labels"]["app.kubernetes.io/name"]
        == "agent-local"
    )
    assert set(volumes(statefulset)) == {
        "data-dir",
        "cache-dir",
        "client-cert",
        "ca-bundle",
        "config",
    }


def test_no_pod_volumes_when_both_claims_are_templates() -> None:
    """Claim templates supply both volumes without explicit pod volume entries."""
    docs = render(
        {
            "workload": {"kind": "StatefulSet"},
            "persistence": {name: {"mode": "volumeClaimTemplate"} for name in ("data", "cache")},
        }
    )
    assert "volumes" not in resource(docs, "StatefulSet")["spec"]["template"]["spec"]


@pytest.mark.parametrize("kind", ("DaemonSet", "statefulset", "", 1))
def test_schema_rejects_invalid_workload_kind(kind: str | int) -> None:
    """Only the exact Deployment and StatefulSet kind values are accepted."""
    assert_invalid({"workload": {"kind": kind}}, "workload")


@pytest.mark.parametrize("name", ("data", "cache"))
@pytest.mark.parametrize("mode", ("invalid", "volumeClaimTemplate"))
def test_deployment_rejects_invalid_storage_mode(
    name: str, mode: str, chart_with_legacy_defaults: Path
) -> None:
    """Deployments reject unknown modes and StatefulSet claim templates."""
    assert_invalid({"persistence": {name: {"mode": mode}}}, "mode")
    assert_invalid({"persistence": {name: {"mode": mode}}}, "mode", chart_with_legacy_defaults)


@pytest.mark.parametrize("name", ("data", "cache"))
@pytest.mark.parametrize("mode", ("emptyDir", "ephemeral", "volumeClaimTemplate"))
def test_unused_claim_name_does_not_change_storage_mode(name: str, mode: str) -> None:
    """Only shared PVC mode uses an existing claim name."""
    expected = render({"workload": {"kind": "StatefulSet"}, "persistence": {name: {"mode": mode}}})
    assert (
        render(
            {
                "workload": {"kind": "StatefulSet"},
                "persistence": {
                    name: {"mode": mode, "persistentVolumeClaim": {"claimName": "existing"}}
                },
            }
        )
        == expected
    )


@pytest.mark.parametrize(
    "legacy",
    [
        pytest.param({"enabled": True}, id="enabled"),
        pytest.param({"persistentVolumeClaim": {"claimName": "old"}}, id="existing-claim"),
    ],
)
def test_explicit_cache_mode_preserves_legacy_claim_settings(legacy: dict[str, Any]) -> None:
    """Changing the storage mode keeps legacy cache provisioning settings until migrated."""
    persistence = {
        **legacy,
        "persistentVolumeClaim": {**legacy.get("persistentVolumeClaim", {}), "storage": "7Gi"},
        "cache": {"mode": "ephemeral", "persistentVolumeClaim": {"storage": "99Gi"}},
    }
    docs = render({"persistence": persistence})
    claim = volumes(resource(docs, "Deployment"))["cache-dir"]["ephemeral"]["volumeClaimTemplate"]
    assert claim["spec"]["resources"]["requests"]["storage"] == "7Gi"
    assert not any(doc["kind"] == "PersistentVolumeClaim" for doc in docs)


def test_rwo_multiple_replicas_share_one_claim() -> None:
    """ReadWriteOnce permits multiple pods on one node, so shared claims remain valid."""
    docs = render({"replicaCount": 3, "persistence": {"cache": {"enabled": True}}})
    deployment = resource(docs, "Deployment")
    claim = resource(docs, "PersistentVolumeClaim")
    assert deployment["spec"]["replicas"] == 3
    assert (
        volumes(deployment)["cache-dir"]["persistentVolumeClaim"]["claimName"]
        == claim["metadata"]["name"]
    )
    assert claim["spec"]["accessModes"] == ["ReadWriteOnce"]
    assert {doc["metadata"]["name"] for doc in docs if doc["kind"] == "PersistentVolumeClaim"} == {
        NAME + "-cache",
    }


def test_legacy_existing_claim_ignores_modern_access_mode() -> None:
    """Unused modern access modes must not invalidate a legacy existing claim."""
    docs = render(
        {
            "replicaCount": 2,
            "persistence": {
                "persistentVolumeClaim": {"claimName": "legacy-existing"},
                "cache": {
                    "enabled": True,
                    "persistentVolumeClaim": {"accessMode": "ReadWriteOncePod"},
                },
            },
        }
    )
    assert volumes(resource(docs, "Deployment"))["cache-dir"]["persistentVolumeClaim"] == {
        "claimName": "legacy-existing",
    }
    assert not any(doc["kind"] == "PersistentVolumeClaim" for doc in docs)


@pytest.mark.parametrize(
    "kind,mode", [("Deployment", "ephemeral"), ("StatefulSet", "volumeClaimTemplate")]
)
def test_single_pod_access_mode_is_valid_for_independent_claims(kind: str, mode: str) -> None:
    """Per-pod claims allow ReadWriteOncePod with multiple replicas."""
    docs = render(
        {
            "workload": {"kind": kind},
            "replicaCount": 3,
            "persistence": {
                name: {
                    "mode": mode,
                    "persistentVolumeClaim": {"accessMode": "ReadWriteOncePod"},
                }
                for name in ("data", "cache")
            },
        }
    )
    workload = resource(docs, kind)
    assert workload["spec"]["replicas"] == 3
    assert not any(doc["kind"] == "PersistentVolumeClaim" for doc in docs)
    if kind == "Deployment":
        claims = {
            name: volume["ephemeral"]["volumeClaimTemplate"]
            for name, volume in volumes(workload).items()
        }
    else:
        claims = {
            claim["metadata"]["name"]: claim for claim in workload["spec"]["volumeClaimTemplates"]
        }
    assert {name: claim["spec"]["accessModes"] for name, claim in claims.items()} == {
        "data-dir": ["ReadWriteOncePod"],
        "cache-dir": ["ReadWriteOncePod"],
    }


@pytest.mark.parametrize("kind", ("Deployment", "StatefulSet"))
def test_zero_replicas_is_allowed_for_migration(kind: str) -> None:
    """Scaling to zero remains available for controller migrations."""
    docs = render({"replicaCount": 0, "workload": {"kind": kind}})
    assert resource(docs, kind)["spec"]["replicas"] == 0


@pytest.mark.parametrize("size_limit", (None, ""), ids=("null", "empty"))
def test_empty_dir_accepts_unlimited_storage(size_limit: str | None) -> None:
    """Both directories preserve the legacy unset-limit configuration."""
    values = {
        "persistence": {name: {"emptyDir": {"sizeLimit": size_limit}} for name in ("data", "cache")}
    }
    docs = render(values)
    for volume in volumes(resource(docs, "Deployment")).values():
        assert not volume["emptyDir"].get("sizeLimit")
    lint = run_helm("lint", values)
    assert lint.returncode == 0, lint.stdout + lint.stderr


@pytest.mark.parametrize("volume_name", ("data", "cache", "legacy"))
def test_existing_claim_needs_no_provisioning_settings(volume_name: str) -> None:
    """Pre-provisioned claims ignore storage and access-mode provisioning settings."""
    settings = {
        "enabled": True,
        "persistentVolumeClaim": {
            "claimName": "preprovisioned",
            "storage": None,
            "accessMode": None,
        },
    }
    persistence = settings if volume_name == "legacy" else {volume_name: settings}
    values = {"persistence": persistence}
    docs = render(values)
    name = "cache" if volume_name == "legacy" else volume_name
    assert volumes(resource(docs, "Deployment"))[name + "-dir"]["persistentVolumeClaim"] == {
        "claimName": "preprovisioned",
    }
    assert not any(doc["kind"] == "PersistentVolumeClaim" for doc in docs)
    lint = run_helm("lint", values)
    assert lint.returncode == 0, lint.stdout + lint.stderr


@pytest.fixture
def chart_with_legacy_defaults(tmp_path: Path) -> Path:
    """Reproduce --reuse-values keeping defaults from before workload and mode options."""
    chart = tmp_path / "agent-local"
    shutil.copytree(CHART, chart)
    values_path = chart / "values.yaml"
    values = yaml.safe_load(values_path.read_text())
    values.pop("workload")
    for name in ("data", "cache"):
        values["persistence"][name].pop("mode")
        values["persistence"][name]["persistentVolumeClaim"].pop("annotations")
    values["persistence"]["persistentVolumeClaim"].pop("annotations")
    values_path.write_text(yaml.safe_dump(values))
    return chart


@pytest.mark.parametrize(
    "values",
    [
        pytest.param({}, id="deployment-default"),
        pytest.param({"persistence": {"enabled": True}}, id="legacy-cache"),
        pytest.param(
            {
                "workload": {"kind": "StatefulSet"},
                "persistence": {"cache": {"mode": "volumeClaimTemplate"}},
            },
            id="opt-in-statefulset",
        ),
        pytest.param(
            {
                "workload": {
                    "kind": "StatefulSet",
                    "statefulSet": {"updateStrategy": {"type": "OnDelete"}},
                },
                "persistence": {"cache": {"mode": "volumeClaimTemplate"}},
            },
            id="partial-statefulset-options",
        ),
    ],
)
def test_reusing_legacy_defaults(chart_with_legacy_defaults: Path, values: dict[str, Any]) -> None:
    """Old releases can reuse values, including when opting into StatefulSet storage."""
    assert render(values, chart_with_legacy_defaults, is_upgrade=True) == render(
        values, is_upgrade=True
    )
    lint = run_helm("lint", values, chart_with_legacy_defaults)
    assert lint.returncode == 0, lint.stdout + lint.stderr


@pytest.mark.parametrize(
    "release_name,fullname_override",
    [
        pytest.param("123", "", id="numeric-release"),
        pytest.param("agents.example", "", id="dotted-release"),
        pytest.param("storage-test", "123-agent", id="numeric-override"),
        pytest.param("storage-test", "agents.example", id="dotted-override"),
        pytest.param("storage-test", "1" * 62 + "a", id="maximum-length-override"),
        pytest.param("storage-test", "1" * 56 + "-suffix", id="truncated-hyphen"),
        pytest.param("a" * 53, "", id="maximum-length-release"),
        pytest.param("storage-test", "a" * 51 + "-suffix", id="statefulset-truncated-hyphen"),
    ],
)
def test_statefulset_names_fit_kubernetes_limits(release_name: str, fullname_override: str) -> None:
    """StatefulSet names leave room for revision labels and use valid Service names."""
    docs = render(
        {"workload": {"kind": "StatefulSet"}, "fullnameOverride": fullname_override},
        release_name=release_name,
    )
    service = resource(docs, "Service")
    statefulset = resource(docs, "StatefulSet")
    name = service["metadata"]["name"]
    assert re.fullmatch(r"[a-z]([-a-z0-9]*[a-z0-9])?", name)
    assert len(name) <= 63
    assert statefulset["spec"]["serviceName"] == name
    assert service["spec"]["selector"] == statefulset["spec"]["selector"]["matchLabels"]
    statefulset_name = statefulset["metadata"]["name"]
    assert re.fullmatch(r"[a-z0-9]([-a-z0-9]*[a-z0-9])?", statefulset_name)
    assert len(statefulset_name) <= 52
    deployment = resource(
        render({"fullnameOverride": fullname_override}, release_name=release_name), "Deployment"
    )
    assert deployment["metadata"]["name"] == (fullname_override or f"{release_name}-agent-local")[
        :63
    ].rstrip("-")


@pytest.mark.parametrize(
    "name",
    (
        "SCALR_AGENT_CACHE_DIR",
        "SCALR_AGENT_WORKER_DRAIN_TIMEOUT",
        "SCALR_AGENT_TLS_CERT_FILE",
        "SCALR_AGENT_TLS_KEY_FILE",
    ),
)
def test_extra_env_rejects_chart_controlled_variables(name: str) -> None:
    """Chart-managed environment variables cannot be duplicated through extraEnv."""
    result = run_helm("template", {"extraEnv": {name: "custom"}})
    assert result.returncode != 0
    assert name in result.stderr
    assert "controlled by the Helm chart" in result.stderr


def test_legacy_numeric_values_are_accepted() -> None:
    """String replica counts and numeric storage quantities keep rendering as before."""
    values = {
        "replicaCount": "2",
        "persistence": {
            "cache": {"enabled": True, "persistentVolumeClaim": {"storage": 4294967296}}
        },
    }
    docs = render(values)
    assert resource(docs, "Deployment")["spec"]["replicas"] == 2
    assert resource(docs, "PersistentVolumeClaim")["spec"]["resources"]["requests"] == {
        "storage": 4294967296,
    }
    lint = run_helm("lint", values)
    assert lint.returncode == 0, lint.stdout + lint.stderr
