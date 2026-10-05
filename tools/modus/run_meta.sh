# Sourced by run.sh and baseline.sh. Not run on its own.
#
# write_run_meta <workspace>: writes <workspace>/run_meta.yaml, the facts the
# wrapper knows authoritatively (harness, repo revision, model, installed
# versions) for score.py --record to pick up, rather than trusting the agent's
# own provenance block. Reads AGENT_CMD and SCRIPT_DIR from the caller.
# Versions are recorded, not pinned. container is the image id when
# run_container.sh launched the run, else false.
write_run_meta() {
    local out="$1/run_meta.yaml"
    local harness tool_sha model r_pkgs
    harness="$(awk '{print $1}' <<< "$AGENT_CMD")"
    tool_sha="${PMX_TOOL_SHA:-$(git -C "$SCRIPT_DIR" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)}"
    # --model straight off AGENT_CMD: more trustworthy than the agent's own
    # provenance.model, seen reporting an estimation method or left blank.
    model="$(grep -oE -- '--model[= ]+[^ ]+' <<< "$AGENT_CMD" | sed -E 's/--model[= ]+//' || true)"
    r_pkgs="$(Rscript -e 'for (p in c("nlmixr2", "rxode2", "mrgsolve", "nlme"))
        cat(p, tryCatch(as.character(packageVersion(p)), error = function(e) "none"), "\n")' 2>/dev/null || true)"
    ver() { "$@" 2>/dev/null | head -1 | tr -d '"' || true; }
    {
        echo "harness: \"${harness}\""
        echo "tool_sha: \"${tool_sha}\""
        echo "model: \"${model}\""
        echo "agent_cmd: \"$(printf '%s' "$AGENT_CMD" | sed 's/"/\\"/g')\""
        echo "env:"
        echo "  container: \"${PMX_CONTAINER:-false}\""
        echo "  harness_version: \"$(ver "$harness" --version)\""
        echo "  r: \"$(ver R --version)\""
        echo "  python: \"$(ver python3 --version)\""
        echo "  r_packages:"
        while read -r p v; do [ -n "$p" ] && echo "    $p: \"$v\""; done <<< "$r_pkgs"
    } > "$out"
}
