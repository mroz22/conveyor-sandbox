#!/usr/bin/env bash
# verify.sh — acceptance-criteria check for the guinea-pig page.
# This is the proof-of-concept gate: it asserts every testable criterion from
# the plan (issue #1). Exits non-zero on the first failure.
set -uo pipefail

cd "$(dirname "$0")/.."

fail=0
pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=1; }

echo "== 1. Required files exist =="
for f in index.html style.css .nojekyll; do
  [ -f "$f" ] && pass "$f exists" || bad "$f missing"
done

echo "== 2. Single static page, no build step (no framework configs) =="
if [ -f package.json ]; then bad "package.json present (should be plain HTML/CSS)"; else pass "no package.json / build step"; fi

echo "== 3. All required sections present =="
for id in jak-vypadaji co-ji kde-bydli starat zajimavosti; do
  grep -q "id=\"$id\"" index.html && pass "section #$id" || bad "section #$id missing"
done

echo "== 4. Base font-size >= 20px =="
# Pull the first html{ ... font-size: NNpx } base rule.
base_fs=$(grep -Eo 'font-size:[[:space:]]*[0-9]+px' style.css | grep -Eo '[0-9]+' | head -1)
if [ -n "$base_fs" ] && [ "$base_fs" -ge 20 ]; then
  pass "base font-size is ${base_fs}px (>= 20)"
else
  bad "base font-size is '${base_fs:-none}px' (< 20 or not found)"
fi

echo "== 5. No JavaScript =="
if grep -qiE '<script|onclick=|onload=' index.html style.css; then
  bad "found script/JS handler"
else
  pass "no <script> or inline JS handlers"
fi

echo "== 6. No external URLs / outbound links in index.html and style.css =="
if grep -nE 'https?://' index.html style.css; then
  bad "external http(s):// URL found above"
else
  pass "no http(s):// in index.html or style.css"
fi

echo "== 7. Every <img> has an alt attribute =="
imgs_total=$(grep -oE '<img[^>]*>' index.html | wc -l | tr -d ' ')
imgs_noalt=$(grep -oE '<img[^>]*>' index.html | grep -vc 'alt=')
if [ "$imgs_noalt" -eq 0 ]; then
  pass "all $imgs_total <img> tags have alt="
else
  bad "$imgs_noalt of $imgs_total <img> tags missing alt="
fi

echo "== 8. All referenced images are local and exist =="
# every src must point inside images/ (no external image hosts)
srcs=$(grep -oE 'src="[^"]+"' index.html | sed -E 's/src="([^"]+)"/\1/')
img_count=0
for s in $srcs; do
  case "$s" in
    http*://*) bad "external image src: $s" ;;
    images/*)
      if [ -f "$s" ]; then pass "image exists: $s"; img_count=$((img_count+1));
      else bad "referenced image missing: $s"; fi ;;
    *) bad "unexpected src (not under images/): $s" ;;
  esac
done

echo "== 9. At least 4 images (plan floor) =="
on_disk=$(find images -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) | wc -l | tr -d ' ')
if [ "$on_disk" -ge 4 ]; then pass "$on_disk image files on disk (>= 4)"; else bad "only $on_disk image files (< 4)"; fi

echo "== 10. Each content section has at least one image (image-per-concept) =="
# crude: count <figure> blocks; expect one per section minimum (>=5)
figs=$(grep -c '<figure>' index.html)
if [ "$figs" -ge 5 ]; then pass "$figs <figure> blocks (>= 5 sections)"; else bad "only $figs <figure> blocks (< 5)"; fi

echo
if [ "$fail" -eq 0 ]; then
  echo -e "\033[32mAll acceptance criteria passed.\033[0m"
  exit 0
else
  echo -e "\033[31mAcceptance criteria FAILED.\033[0m"
  exit 1
fi
