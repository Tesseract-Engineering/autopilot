. "$(dirname "$0")/lib.sh"
new_repo; start_run default '{"slices":[{"id":"a","goal":"g","allowed_files":["src/math.sh"]}]}'
V="$SCRIPTS/verify-finding.sh"; F=".autopilot/runs/$RUN"
# (e) a finding whose repro passes is discarded
jq -n '{id:"f1",title:"add is wrong",test_path:"tests/test_f1.sh",test_code:". src/math.sh\n[ \"$(add 2 2)\" = 4 ] || exit 1"}' > $F/f1.json
expect 1 "repro that passes -> DISCARDED"       "$V" "$RUN" $F/f1.json; has "DISCARDED"; has "repro passes"
expect 1 "discarded repro file removed"         test -e tests/test_f1.sh
# a finding whose repro fails is kept
jq -n '{id:"f2",title:"mul(0,x)",test_path:"tests/test_f2.sh",test_code:". src/math.sh\n[ \"$(mul 2 0)\" = 2 ] || exit 1"}' > $F/f2.json
expect 0 "repro that fails -> KEPT"             "$V" "$RUN" $F/f2.json; has "KEPT"
expect 0 "kept repro joins the suite"           test -f tests/test_f2.sh
expect 0 "result recorded"                      grep -q KEPT $F/findings/f2.result
# no repro at all
jq -n '{id:"f3",title:"style: rename var"}' > $F/f3.json
expect 1 "finding without repro -> DISCARDED"   "$V" "$RUN" $F/f3.json; has "no repro test"
# repro that errors instead of failing
jq -n '{id:"f4",title:"x",test_path:"tests/test_f4.sh",test_code:"exit 2"}' > $F/f4.json
expect 1 "erroring repro -> DISCARDED"          "$V" "$RUN" $F/f4.json; has "errored"
# repro outside test paths / escaping repo
jq -n '{id:"f5",title:"x",test_path:"src/evil.sh",test_code:"exit 1"}' > $F/f5.json
expect 1 "repro outside test_globs -> DISCARDED" "$V" "$RUN" $F/f5.json; has "does not match test_globs"
expect 1 "nothing written to src"               test -e src/evil.sh
jq -n '{id:"f6",title:"x",test_path:"tests/../../x.sh",test_code:"exit 1"}' > $F/f6.json
expect 1 "path traversal -> DISCARDED"          "$V" "$RUN" $F/f6.json; has "relative inside"
jq -n '{id:"f7",title:"x",test_path:"tests/test_add.sh",test_code:"exit 1"}' > $F/f7.json
expect 1 "overwriting an existing test -> DISCARDED" "$V" "$RUN" $F/f7.json; has "already exists"
expect 0 "existing test untouched"              git diff --quiet tests/test_add.sh
finish
