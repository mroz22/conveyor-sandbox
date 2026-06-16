#!/usr/bin/env bash
# verify.sh — acceptance-criteria check for the guinea-pig page.
# This is the proof-of-concept gate: it asserts every testable criterion from
# the plan (issue #1). Runs ALL checks and exits non-zero if any of them failed.
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

echo "== 4. Base font-size >= 20px (anchored to the html { } rule) =="
# Read font-size only from inside the html { ... } block, so an unrelated px
# rule elsewhere in the file can never satisfy or break this assertion.
base_fs=$(awk '/html[[:space:]]*\{/{f=1} f{print} /\}/{if(f)exit}' style.css \
          | grep -oE 'font-size:[[:space:]]*[0-9]+px' | grep -oE '[0-9]+' | head -1)
if [ -n "$base_fs" ] && [ "$base_fs" -ge 20 ]; then
  pass "html base font-size is ${base_fs}px (>= 20)"
else
  bad "html base font-size is '${base_fs:-none}px' (< 20 or not found in html{})"
fi

echo "== 5. No JavaScript =="
if grep -qiE '<script|onclick=|onload=' index.html style.css; then
  bad "found script/JS handler"
else
  pass "no <script> or inline JS handlers"
fi

echo "== 6. No external URLs / outbound links (index.html, style.css, favicon.svg) =="
# favicon.svg legitimately contains the SVG XML namespace; whitelist only that.
ext=$( { grep -nE 'https?://' index.html style.css; \
         grep -nE 'https?://' favicon.svg | grep -v 'www\.w3\.org/2000/svg'; } 2>/dev/null )
if [ -n "$ext" ]; then
  printf '%s\n' "$ext"
  bad "external http(s):// URL found above"
else
  pass "no external http(s):// URLs (SVG namespace whitelisted)"
fi

echo "== 7. Every <img> has a non-empty alt attribute =="
bad_alt=0
while IFS= read -r tag; do
  printf '%s' "$tag" | grep -qE '[[:space:]]alt="[^"]+"' || { bad "img without non-empty alt: $tag"; bad_alt=1; }
done < <(grep -oE '<img[^>]*>' index.html)
[ "$bad_alt" -eq 0 ] && pass "all <img> tags have a non-empty alt="

echo "== 8. All referenced images are local and exist =="
while IFS= read -r s; do
  case "$s" in
    http*://*) bad "external image src: $s" ;;
    images/*)  [ -f "$s" ] && pass "image exists: $s" || bad "referenced image missing: $s" ;;
    *) bad "unexpected src (not under images/): $s" ;;
  esac
done < <(grep -oE 'src="[^"]+"' index.html | sed -E 's/src="([^"]+)"/\1/')

echo "== 9. At least 4 images on disk (plan floor) =="
on_disk=$(find images -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) | wc -l | tr -d ' ')
if [ "$on_disk" -ge 4 ]; then pass "$on_disk image files on disk (>= 4)"; else bad "only $on_disk image files (< 4)"; fi

echo "== 10. Each content section has at least one image (image-per-concept) =="
missing=$(awk '
  /<section /{ if(insec && !hasimg) print secid;
               insec=1; hasimg=0;
               if(match($0,/id="[^"]+"/)) secid=substr($0,RSTART+4,RLENGTH-5) }
  insec && /<img/{ hasimg=1 }
  END{ if(insec && !hasimg) print secid }
' index.html)
if [ -z "$missing" ]; then pass "every <section> has >= 1 <img>"; else bad "section(s) without an image: $missing"; fi

echo "== 11. Every in-page anchor (#id) resolves to a matching id =="
bad_anchor=0
while IFS= read -r a; do
  grep -q "id=\"$a\"" index.html || { bad "anchor #$a has no matching id"; bad_anchor=1; }
done < <(grep -oE 'href="#[^"]+"' index.html | sed -E 's/href="#([^"]+)"/\1/')
[ "$bad_anchor" -eq 0 ] && pass "all #anchors resolve to an id"

echo "== 12. 'Kde bydlí' covers cage types incl. a safely-framed multi-level cage =="
sec=$(awk '/<section id="kde-bydli"/{f=1} f{print} f&&/<\/section>/{exit}' index.html)
img_in_sec=$(printf '%s' "$sec" | grep -oE '<img' | wc -l | tr -d ' ')
[ "$img_in_sec" -ge 3 ] && pass "kde-bydli has $img_in_sec images (>= 3 cage types)" \
  || bad "kde-bydli has only $img_in_sec images (< 3 cage types)"
printf '%s' "$sec" | grep -qi 'vícepatrov' \
  && pass "multi-level (vícepatrová) cage mentioned" || bad "multi-level cage not mentioned"
if printf '%s' "$sec" | grep -qi 'rampa' \
   && printf '%s' "$sec" | grep -qi 'pevná' \
   && printf '%s' "$sec" | grep -qi 'nespadl'; then
  pass "multi-level cage has safety framing (ramp + solid + can't-fall)"
else
  bad "multi-level cage missing safety framing (needs rampa + pevná + nespadl)"
fi
if printf '%s' "$sec" | grep -qi 'rozmazlit'; then
  pass "'Jak mořče rozmazlit' premium-care tips present"
else
  bad "premium-care tips ('Jak mořče rozmazlit') missing"
fi
for im in images/klec-vicepatrova.svg images/klec-domecek-tunely.svg; do
  grep -qF "$im" index.html && pass "references $im" || bad "missing reference to $im"
done

echo
if [ "$fail" -eq 0 ]; then
  echo -e "\033[32mAll acceptance criteria passed.\033[0m"
  exit 0
else
  echo -e "\033[31mAcceptance criteria FAILED.\033[0m"
  exit 1
fi
