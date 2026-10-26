#!/usr/bin/env bash
#
# Regression for issue #233: downstream filters must see that pdftopdf
# has already applied page management and generated the requested copies.
# Run from the top-level build directory, like testfilters.sh.
#
set -euo pipefail

CC="${CC:-cc}"
if [[ ! -x ./testfilters ]]; then
  echo "testfilters harness not found" >&2
  exit 99
fi
if ! pkg-config --exists pdfio; then
  echo "pkg-config cannot find pdfio; skipping." >&2
  exit 77
fi

WORKDIR="$(mktemp -d ./pdftopdf-comments.XXXXXX)"
trap 'rm -rf "${WORKDIR}"' EXIT
CHECKER="${WORKDIR}/check"
# Deliberate word splitting for compiler/linker flags, as in the other tests.
"${CC}" -std=gnu11 $(pkg-config --cflags pdfio) \
  cupsfilters/test-pdftopdf-comments.c $(pkg-config --libs pdfio) \
  -o "${CHECKER}"
"${CHECKER}" --create "${WORKDIR}/input.pdf"

status=0
check() {
  local name="$1" copies="$2" options="$3" pages="$4"
  local output="${WORKDIR}/${name}.pdf" cases="${WORKDIR}/cases.txt"

  printf '%s\tapplication/pdf\t%s\tapplication/pdf\tGeneric\tPDF Color 2\t1\t1\tapplication/pdf\t42\ttest-user\tcomments\t%s\t%s\tpdftopdf\n' \
    "${WORKDIR}/input.pdf" "${output}" "${copies}" \
    "PageSize=A4 ${options}" > "${cases}"
  if ! ./testfilters "${cases}" > "${WORKDIR}/filter.log" 2>&1 ||
     ! "${CHECKER}" "${output}" "${pages}"; then
    cat "${WORKDIR}/filter.log" >&2
    echo "FAIL: ${name}" >&2
    status=1
    return
  fi
  # qpdf must report no warnings or repairs, not just recover a readable PDF.
  if command -v qpdf > /dev/null && ! qpdf --check "${output}"; then
    status=1
    return
  fi
  echo "PASS: ${name}"
}

check default          1 ""                                      "1,2,3,4"
check number-up        1 "number-up=2"                           "12,34"
check page-ranges      1 "page-ranges=3-4"                        "3,4"
check combined         1 "number-up=2 page-ranges=3-4"            "34"
check copies-argument  2 ""                                      "1,2,3,4,1,2,3,4"
check copies-option    1 "copies=2"                              "1,2,3,4,1,2,3,4"
check collate          2 "Collate=True page-ranges=3-4"           "3,4,3,4"
check ipp-collate      2 "multiple-document-handling=separate-documents-collated-copies number-up=2" "12,34,12,34"
check single-copy     1 "Collate=False"                          "1,2,3,4"
check fast-copy       2 "print-scaling=none page-ranges=3-4"     "3,4,3,4"

exit "${status}"
