#!/usr/bin/env bash
# ============================================================================
# UTNixOS_Pro 容器测试总入口（在宿主机运行，需要 docker）
#
#   bash test/container-test.sh
#
# 流程：
#   1. 在 golang 容器中构建 webui 二进制 + 运行 Go 单元测试
#   2. 在 Debian 容器中测试脚本功能（一键安装/菜单/更新/回滚/引导模式）
#   3. 在 Debian 容器中测试 Web 管理面板（PAM 登录 + 全部 API）
#
# 产物：test/result/ 下保存每次运行日志
# ============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."
REPO="$(pwd)"
IMG_GO="docker.m.daocloud.io/library/golang:1.22"
IMG_DEB="docker.m.daocloud.io/library/debian:bookworm"
BIN_DIR="$REPO/.test-bin"
RESULT_DIR="$REPO/test/result"
mkdir -p "$BIN_DIR" "$RESULT_DIR"
TS="$(date +%Y%m%d-%H%M%S)"
ALL_PASS=1

echo "================ UTNixOS_Pro 容器测试 ================"
echo "仓库: $REPO"

echo ""
echo "== 步骤 1：构建 webui + Go 单元测试 =="
if docker run --rm -v "$REPO":/app -w /app/webui "$IMG_GO" \
     sh -c "GOFLAGS=-buildvcs=false go build -o /tmp/webui ./cmd/webui \
            && cp /tmp/webui /app/.test-bin/webui \
            && GOFLAGS=-buildvcs=false go test ./... > /app/.test-bin/go-test.log 2>&1" \
   && [ -x "$BIN_DIR/webui" ]; then
  echo "  [PASS] webui 构建成功: $BIN_DIR/webui"
  if grep -q '^ok' "$BIN_DIR/go-test.log"; then
    echo "  [PASS] Go 单元测试通过:"
    grep '^ok' "$BIN_DIR/go-test.log" | sed 's/^/         /'
  else
    echo "  [FAIL] Go 单元测试未通过"; cat "$BIN_DIR/go-test.log"; ALL_PASS=0
  fi
else
  echo "  [FAIL] webui 构建失败"; ALL_PASS=0
fi

echo ""
echo "== 步骤 2：脚本功能测试（Debian 容器） =="
docker run --rm --tmpfs /mnt:rw,size=64m \
  -v "$REPO":/repo:ro \
  -v "$REPO/test/script-test.sh":/script-test.sh:ro \
  "$IMG_DEB" bash -c "
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq git rsync curl util-linux >/dev/null 2>&1
    bash /script-test.sh
  " 2>&1 | tee "$RESULT_DIR/script-test-$TS.log"
if [ "${PIPESTATUS[0]}" -eq 0 ]; then
  echo "  [PASS] 脚本功能测试全部通过"
else
  echo "  [FAIL] 脚本功能测试存在失败"; ALL_PASS=0
fi

echo ""
echo "== 步骤 3：Web 管理面板测试（Debian 容器） =="
docker run --rm \
  -v "$REPO":/repo:ro \
  -v "$BIN_DIR":/webui-bin:ro \
  -v "$REPO/test/webui-test.sh":/webui-test.sh:ro \
  "$IMG_DEB" bash -c "
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq pamtester curl rsync python3 >/dev/null 2>&1
    bash /webui-test.sh
  " 2>&1 | tee "$RESULT_DIR/webui-test-$TS.log"
if [ "${PIPESTATUS[0]}" -eq 0 ]; then
  echo "  [PASS] WebUI 测试全部通过"
else
  echo "  [FAIL] WebUI 测试存在失败"; ALL_PASS=0
fi

echo ""
echo "============================================================"
if [ "$ALL_PASS" -eq 0 ]; then
  echo "UTNixOS_Pro 容器测试：存在失败，详见 test/result/ 日志"
  exit 1
fi
echo "UTNixOS_Pro 容器测试：全部通过 ✓"
echo "日志目录：test/result/"
