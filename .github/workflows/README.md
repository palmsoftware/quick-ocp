# GitHub Actions Workflows

This directory contains the workflows for the quick-ocp action.

## Main Workflows

### nightly.yml
**Purpose:** Nightly testing of the action with various OCP versions

**Runs:** Every night at scheduled time
**Tests:** Full action with multiple OCP versions

---

### pre-main.yml
**Purpose:** Test changes before merging to main branch

**Runs:** On push to main, PRs to main
**Tests:** Full action workflow

---

### update-major-tag.yml
**Purpose:** Automatically update major version tags (v0, v1, etc.)

---

## Cache Testing Workflows

### pr-cache-test.yml ⭐ NEW
**Purpose:** PR check that tests **both** download paths

**Runs:** On PRs that modify download scripts
**Tests:**
1. ✅ Normal mirror download (primary path)
2. ✅ Cache failover download (backup path)
3. ✅ Error handling (missing cache)

**Features:**
- Parallel execution (fast)
- Tests both code paths
- Validates error handling
- Summary report

**Manual Trigger:**
```bash
gh workflow run pr-cache-test.yml -f test_version=2.54.0
```

---

### test-cache-only.yml
**Purpose:** Quick test of cache mechanism only

**Runs:** Manual trigger
**Tests:**
- Direct cache download
- Cache existence checks
- Error handling

**Usage:**
```bash
gh workflow run test-cache-only.yml \
  -f crc_version=2.54.0 \
  -f simulate_mirror_failure=true
```

**Time:** ~2-3 minutes

---

### test-cache-integration.yml
**Purpose:** Test cache integration with full action

**Runs:** Manual trigger
**Tests:**
- Version detection
- Cache failover integration
- Full action flow (optional cluster start)

**Usage:**
```bash
gh workflow run test-cache-integration.yml \
  -f ocp_version=4.19 \
  -f force_cache=true \
  -f skip_cluster_start=true
```

**Time:** ~5 minutes (without cluster), ~30 minutes (with cluster)

---

## Workflow Comparison

| Workflow | When | Duration | Purpose |
|----------|------|----------|---------|
| **nightly.yml** | Nightly | ~30 min | Full integration testing |
| **pre-main.yml** | PRs to main | ~30 min | Pre-merge validation |
| **pr-cache-test.yml** ⭐ | PRs (cache changes) | ~5 min | Validate both download paths |
| **test-cache-only.yml** | Manual | ~2 min | Quick cache testing |
| **test-cache-integration.yml** | Manual | ~5 min | Full cache integration |

## Cache Testing Strategy

### On Pull Requests
**Workflow:** `pr-cache-test.yml`

Automatically tests:
- Normal download path (mirror)
- Cache failover path
- Error handling

This ensures changes don't break either download method.

### Manual Testing
**Quick Test:** `test-cache-only.yml`
- Fast feedback
- Cache mechanism only

**Full Test:** `test-cache-integration.yml`
- Complete integration
- Version detection
- Optional cluster start

### Nightly Testing
**Workflow:** `nightly.yml`
- Full action testing
- Multiple OCP versions
- Normal mirror path (no cache forced)

## Environment Variables

All cache workflows support:

```yaml
env:
  SIMULATE_MIRROR_FAILURE: true/false  # Force cache or test normal path
  CACHE_REGISTRY: quay.io              # Override registry
  CACHE_IMAGE_NAME: bapalm/quick-ocp-cache  # Override image name
```

## Testing Checklist

Before merging cache-related changes:

- [ ] `pr-cache-test.yml` passes (auto-runs on PR)
- [ ] Both download paths tested successfully
- [ ] Error handling validated
- [ ] Manual test with `test-cache-only.yml` (optional)
- [ ] Manual test with `test-cache-integration.yml` (optional)

## Troubleshooting

### PR Check Fails

Check which path failed:
- **Mirror Path:** Issue with primary download logic
- **Cache Path:** Issue with cache failover logic
- **Error Handling:** Issue with failure scenarios

### Cache Images Not Found

Verify cache images exist:
```bash
curl -s "https://quay.io/api/v1/repository/bapalm/quick-ocp-cache/tag/" | jq -r '.tags[].name'
```

Available versions: 2.51.0, 2.54.0, 2.56.0

### Tests Timeout

Adjust timeouts or skip cluster start:
```yaml
inputs:
  skip_cluster_start: true
```

## Related Documentation

- [CACHE_TESTING.md](../../CACHE_TESTING.md) - Testing guide
- [Cache Repository](https://github.com/bapalm/quick-ocp-cache) - Cache builder
- [Cache Images](https://quay.io/repository/bapalm/quick-ocp-cache) - Quay.io registry

