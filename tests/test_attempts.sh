. "$(dirname "$0")/lib.sh"
new_repo; start_run default '{"slices":[{"id":"a","goal":"g","allowed_files":["src/math.sh"]}]}'
A="$SCRIPTS/attempts.sh"
expect 0 "fresh unit counts 0"            "$A" count "$RUN" a; has 0
expect 0 "fresh unit is pending"          "$A" status "$RUN" a; has pending
expect 0 "check passes while pending"     "$A" check "$RUN" a
expect 0 "incr -> 1"                      "$A" incr "$RUN" a; has 1
expect 0 "incr -> 2"                      "$A" incr "$RUN" a; has 2
expect 0 "still pending at 2/3"           "$A" status "$RUN" a; has pending
expect 0 "incr -> 3"                      "$A" incr "$RUN" a; has 3
expect 0 "escalated at cap"               "$A" status "$RUN" a; has escalated
expect 3 "check exits 3 when escalated"   "$A" check "$RUN" a
expect 0 "reset"                          "$A" reset "$RUN" a
expect 0 "pending after reset"            "$A" status "$RUN" a; has pending
expect 64 "unknown run is a usage error"  "$A" count nope a
expect 64 "bad command is a usage error"  "$A" frob "$RUN" a
finish
