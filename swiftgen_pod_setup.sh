#!/usr/bin/env bash

set -euo pipefail

# setup_swiftgen_pod.sh
# 目的：为一个本地 Pod 仓库快速接入 SwiftGen
# 功能：
# - 创建 SwiftGen 目录与配置文件
# - 创建 Sources/Generated 目录
# - 可选生成占位资源（Assets.xcassets 与 Localizable.strings）
# - 调用 swiftgen 生成 Assets.swift 与 Strings.swift（若已安装）
# - 幂等更新 .podspec：添加 SwiftGen/Sources 子模块与 s.resources 资源配置

# 使用示例：
#  # 最简：传入“组件根目录”（推荐）
#  ## 创建配置, 及索引源码生成; 如果没有资源模板, 创建空模板
#  ✗ bash AppTemplate/Scripts/swiftgen_pod_setup.sh PodsRepo/Demo --create-placeholders
#  ## 创建配置, 及索引源码生成
#  ✗ bash AppTemplate/Scripts/swiftgen_pod_setup.sh PodsRepo/Demo
#  ## 构建依赖
#  ✗ pod install
#

print_usage() {
  cat 1>&2 <<'USAGE'
用法：
  # 在主工程根目录，传入组件根目录
  bash AppTemplate/Scripts/setup_swiftgen_pod.sh PodsRepo/Demo

常用选项：
  --create-placeholders   若缺少资源则创建占位
  --skip-run              仅生成配置与目录，不执行 swiftgen
  --dry-run               只打印计划更改

说明：自动生成 SwiftGen 配置与代码，并增量更新 Podspec（子模块与资源）。
USAGE
}

log_i() { echo "[INFO] $*"; }
log_w() { echo "[WARN] $*"; }
log_e() { echo "[ERR ] $*" 1>&2; }

POD_ROOT=""
PODSPEC_FILE=""
MODULE_NAME=""
ASSETS_PATH=""
STRINGS_PATH=""
SKIP_RUN=0
CREATE_PLACEHOLDERS=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      POD_ROOT="$2"; shift 2 ;;
    --pod-root)
      POD_ROOT="$2"; shift 2 ;;
    --podspec)
      PODSPEC_FILE="$2"; shift 2 ;;
    --module)
      MODULE_NAME="$2"; shift 2 ;;
    --assets)
      ASSETS_PATH="$2"; shift 2 ;;
    --strings)
      STRINGS_PATH="$2"; shift 2 ;;
    --skip-run)
      SKIP_RUN=1; shift ;;
    --create-placeholders)
      CREATE_PLACEHOLDERS=1; shift ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    -h|--help)
      print_usage; exit 0 ;;
    --*)
      log_e "Unknown argument: $1"; print_usage; exit 2 ;;
    *)
      # 位置参数：组件根目录
      if [[ -z "$POD_ROOT" ]]; then
        POD_ROOT="$1"; shift; continue
      else
        log_e "多余的位置参数：$1"; print_usage; exit 2
      fi ;;
  esac
done

# 推断 Pod 根目录
if [[ -z "$POD_ROOT" ]]; then
  POD_ROOT="$(pwd)"
  log_i "未指定 --pod-root，使用当前目录：$POD_ROOT"
fi

if [[ ! -d "$POD_ROOT" ]]; then
  log_e "Pod root not found: $POD_ROOT"
  exit 2
fi

# 自动发现 podspec（若未指定）
find_podspec() {
  local root="$1"
  local candidates=()
  shopt -s nullglob
  candidates+=("$root"/*.podspec)
  candidates+=("$root"/../*.podspec)
  shopt -u nullglob
  if [[ ${#candidates[@]} -eq 0 ]]; then
    return 1
  fi
  if [[ ${#candidates[@]} -eq 1 ]]; then
    echo "${candidates[0]}"
    return 0
  fi
  # 多个时，优先内容包含当前根目录名的 podspec
  local base
  base="$(basename "$root")"
  for f in "${candidates[@]}"; do
    if grep -q "$base/" "$f" 2>/dev/null; then
      echo "$f"; return 0
    fi
  done
  # 否则返回第一个
  echo "${candidates[0]}"
}

if [[ -z "$PODSPEC_FILE" ]]; then
  if PODSPEC_FILE=$(find_podspec "$POD_ROOT"); then
    log_i "自动发现 podspec：$PODSPEC_FILE"
  else
    log_e "未发现 podspec。可通过 --podspec 指定，或在组件根/上级目录放置 *.podspec"
    exit 2
  fi
fi

if [[ ! -f "$PODSPEC_FILE" ]]; then
  log_e "Podspec not found: $PODSPEC_FILE"
  exit 2
fi

# 规范化默认路径
ASSETS_PATH_DEFAULT="$POD_ROOT/Resources/Assets.xcassets"
STRINGS_PATH_DEFAULT="$POD_ROOT/Resources/en.lproj/Localizable.strings"
ASSETS_PATH="${ASSETS_PATH:-$ASSETS_PATH_DEFAULT}"
STRINGS_PATH="${STRINGS_PATH:-$STRINGS_PATH_DEFAULT}"

# 预检测 swiftgen
HAS_SWIFTGEN=0
if command -v swiftgen >/dev/null 2>&1; then
  HAS_SWIFTGEN=1
else
  log_w "未检测到 swiftgen（brew install swiftgen）。将跳过自动生成。"
fi

# 解析模块名
# 以目录名为优先模块名；如用户通过 --module 指定则尊重传入
if [[ -z "$MODULE_NAME" ]]; then
  MODULE_NAME="$(basename "$POD_ROOT")"
fi
log_i "模块名：$MODULE_NAME"

SWIFTGEN_DIR="$POD_ROOT/SwiftGen"
GENERATED_DIR="$POD_ROOT/Sources/Generated"
RESOURCES_DIR="$POD_ROOT/Resources"

ensure_dir() {
  local p="$1"
  if [[ $DRY_RUN -eq 1 ]]; then
    log_i "[dry-run] mkdir -p $p"
  else
    mkdir -p "$p"
  fi
}

write_file() {
  local path="$1"; shift
  local content="$*"
  if [[ $DRY_RUN -eq 1 ]]; then
    log_i "[dry-run] write $path"
    return 0
  fi
  printf "%s" "$content" > "$path"
}

# 从标准输入写入文件（用于多行内容）
write_stdin() {
  local path="$1"
  if [[ $DRY_RUN -eq 1 ]]; then
    log_i "[dry-run] write $path (from stdin)"
    cat > /dev/null
    return 0
  fi
  cat > "$path"
}

append_if_missing() {
  local file="$1"; local needle="$2"; local block="$3"
  if grep -qE "$needle" "$file"; then
    log_i "已存在：$needle"
    return 0
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    log_i "[dry-run] 追加到 $file -> $needle"
    return 0
  fi
  # 尝试在 "Pod::Spec.new do |s|" 块内部靠后位置插入
  # 若存在 "# --- SwiftGen end ---"，则在其前插入；否则在文件末尾前插入（保留 end）
  if grep -n "# --- SwiftGen end ---" "$file" >/dev/null 2>&1; then
    local ln
    ln=$(grep -n "# --- SwiftGen end ---" "$file" | tail -n1 | cut -d: -f1)
    awk -v ln="$ln" -v blk="$block" 'NR==ln{print blk} {print}' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  else
    # 在最后一个 "end" 之前插入
    awk -v blk="$block" '{b[i++]=$0} END{ for (j=0;j<i-1;j++) print b[j]; print blk; print b[i-1]; }' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  fi
}

relpath() {
  # 生成相对路径（以 SwiftGen 配置所在目录为基准）
  python3 - "$SWIFTGEN_DIR" "$1" <<'PY'
import os,sys
base=sys.argv[1]
target=sys.argv[2]
print(os.path.relpath(target, start=base))
PY
}

log_i "创建目录结构……"
ensure_dir "$SWIFTGEN_DIR"
ensure_dir "$GENERATED_DIR"
ensure_dir "$RESOURCES_DIR"

if [[ $CREATE_PLACEHOLDERS -eq 1 ]]; then
  log_i "生成占位资源（如不存在）……"
  # Assets.xcassets
  if [[ ! -d "$ASSETS_PATH" ]]; then
    ensure_dir "$ASSETS_PATH"
    # 占位目录足够，避免写入 Contents.json 以免在 pod install 阶段触发冲突
  fi
  # en.lproj/Localizable.strings
  STRINGS_DIR="$(dirname "$STRINGS_PATH")"
  ensure_dir "$STRINGS_DIR"
  if [[ ! -f "$STRINGS_PATH" ]]; then
    write_file "$STRINGS_PATH" '"string_demo" = "Demo";'
  fi
fi

log_i "写入 SwiftGen 配置……"
REL_ASSETS=$(relpath "$ASSETS_PATH")
REL_STRINGS=$(relpath "$STRINGS_PATH")

EXISTS_ASSETS=0
[[ -d "$ASSETS_PATH" ]] && EXISTS_ASSETS=1

# 仅检测 /Resources/en.lproj/Localizable.strings 是否存在且非空
EXISTS_STRINGS=0
[[ -s "$STRINGS_PATH" ]] && EXISTS_STRINGS=1

SWIFTGEN_YML="$SWIFTGEN_DIR/swiftgen.yml"
{
  echo "## For more info, see SwiftGen documentation"
  echo "## by hubin.h"
  echo "##"
  echo "## 常用指令"
  echo "## brew install swiftgen"
  echo "## cd $(basename \"$POD_ROOT\")/SwiftGen"
  echo "## swiftgen config run --config swiftgen.yml"
  echo
  echo "# ---"
  if [[ $EXISTS_ASSETS -eq 1 ]]; then
    cat <<EOF
xcassets:
  inputs:
    - ${REL_ASSETS}
  outputs:
    - templateName: swift5
      output: ../Sources/Generated/Assets.swift
      bundle: BundleToken.bundle
EOF
    echo
  fi
  if [[ $EXISTS_STRINGS -eq 1 ]]; then
    cat <<EOF
strings:
  inputs:
    - ${REL_STRINGS}
  outputs:
    - templateName: structured-swift5
      output: ../Sources/Generated/Strings.swift
      bundle: BundleToken.bundle
EOF
    echo
  fi
  echo "# ---"
} | write_stdin "$SWIFTGEN_YML"

if [[ $SKIP_RUN -eq 0 ]]; then
  if [[ $HAS_SWIFTGEN -eq 1 ]]; then
    if [[ $EXISTS_ASSETS -eq 1 || $EXISTS_STRINGS -eq 1 ]]; then
      # 预先 lint 配置，便于只生成 strings 时尽早发现问题
      if [[ $DRY_RUN -eq 1 ]]; then
        log_i "[dry-run] (cd $SWIFTGEN_DIR && swiftgen config lint --config swiftgen.yml || true)"
      else
        (cd "$SWIFTGEN_DIR" && swiftgen config lint --config swiftgen.yml) || log_w "swiftgen 配置 lint 出现告警/错误，继续尝试生成"
      fi
      log_i "执行 swiftgen 生成代码……"
      if [[ $DRY_RUN -eq 1 ]]; then
        log_i "[dry-run] (cd $SWIFTGEN_DIR && swiftgen config run --config swiftgen.yml)"
      else
        (cd "$SWIFTGEN_DIR" && swiftgen config run --config swiftgen.yml)
      fi
    else
      log_w "未找到可用的资源输入（Assets/Strings），跳过 swiftgen 生成。"
    fi
  else
    log_w "未安装 swiftgen，已跳过生成。"
  fi
else
  log_i "跳过执行 swiftgen（--skip-run）"
fi

log_i "增量更新 podspec……"

SWIFTGEN_SUBSPEC_BLOCK="  # --- SwiftGen began ---\n  s.subspec 'SwiftGen' do |ss|\n      ss.source_files = '$(basename "$POD_ROOT")/SwiftGen/*'\n  end\n  s.subspec 'Sources' do |ss|\n      ss.source_files = '$(basename "$POD_ROOT")/Sources/Generated/*'\n  end\n  # --- SwiftGen end ---\n"

# 将 $(basename "$POD_ROOT") 替换为真实目录名（相对路径前缀）
REL_ROOT_NAME="$(basename "$POD_ROOT")"
SWIFTGEN_SUBSPEC_BLOCK=${SWIFTGEN_SUBSPEC_BLOCK//\$\(basename \"\$POD_ROOT\"\)/$REL_ROOT_NAME}

# 计算从 podspec 所在目录到组件根目录的相对前缀
PODSPEC_DIR="$(cd "$(dirname "$PODSPEC_FILE")" && pwd)"
REL_PREFIX=$(python3 - "$PODSPEC_DIR" "$POD_ROOT" <<'PY'
import os,sys
base=sys.argv[1]
target=sys.argv[2]
rp=os.path.relpath(target, start=base)
print('' if rp=='.' else rp)
PY
)

[[ -n "$REL_PREFIX" ]] && REL_PREFIX="$REL_PREFIX/"

SWIFTGEN_SUBSPEC_BLOCK="  # --- SwiftGen began ---\n  s.subspec 'SwiftGen' do |ss|\n      ss.source_files = '${REL_PREFIX}SwiftGen/*'\n  end\n  s.subspec 'Sources' do |ss|\n      ss.source_files = '${REL_PREFIX}Sources/Generated/*'\n  end\n  # --- SwiftGen end ---\n"

append_if_missing "$PODSPEC_FILE" "s.subspec 'SwiftGen' do" "$SWIFTGEN_SUBSPEC_BLOCK"

# 资源配置：仅包含 .xcassets 与 .strings（按当前需求精简）
RES_LINE="  s.resources = [\n"
RES_LINE+="    '${REL_PREFIX}Resources/**/*.xcassets',\n"
RES_LINE+="    '${REL_PREFIX}Resources/**/*.strings'\n"
RES_LINE+="  ]\n"
if ! grep -qE "s\.resources\s*=\s*\[.*Resources/\*\*/\*.*\]" "$PODSPEC_FILE"; then
  append_if_missing "$PODSPEC_FILE" "s.resources" "$RES_LINE"
else
  log_i "podspec 已包含 s.resources 配置"
fi

log_i "完成。你现在可以："
echo "  1) 在示例/宿主工程中，执行 pod install 并验证生成的 API（Assets/Strings）"
echo "  2) 打开：$SWIFTGEN_YML"
echo "  3) 查看：$GENERATED_DIR"

