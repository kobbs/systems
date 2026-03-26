# lib/config.sh — INI profile parser.
# Source this file; do not execute it directly.

# ---------------------------------------------------------------------------
# Global state
# ---------------------------------------------------------------------------

# shellcheck disable=SC2034  # variables used by sourcing scripts

declare -gA _CONFIG=()

# ---------------------------------------------------------------------------
# _parse_ini <file>
# Reads an INI file into the global _CONFIG associative array.
# Keys are stored as "section.key". Sectionless keys use an empty section
# prefix (e.g. ".key"). Later calls overlay earlier values (last write wins).
# ---------------------------------------------------------------------------
_parse_ini() {
    local file="$1"
    [[ -f "$file" ]] || return 0

    local section="" line key value

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Skip blanks and comments
        [[ -z "$line" || "$line" == \#* ]] && continue

        # Section header
        if [[ "$line" =~ ^\[([^]]+)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            # Trim whitespace from section name
            section="${section#"${section%%[![:space:]]*}"}"
            section="${section%"${section##*[![:space:]]}"}"
            continue
        fi

        # Key = value pair
        if [[ "$line" == *=* ]]; then
            key="${line%%=*}"
            value="${line#*=}"

            # Trim whitespace from key and value
            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"

            _CONFIG["${section}.${key}"]="$value"
        fi
    done < "$file"
}

# ---------------------------------------------------------------------------
# load_profile <profiles_dir>
# Parses default.conf then overlays local.conf (later values win).
# Exports PROFILE_SECTION_KEY env vars for every entry in _CONFIG.
# ---------------------------------------------------------------------------
load_profile() {
    local profiles_dir="$1"

    _CONFIG=()

    _parse_ini "${profiles_dir}/default.conf"
    _parse_ini "${profiles_dir}/local.conf"

    # Export as PROFILE_SECTION_KEY environment variables
    local compound_key section key var_name
    for compound_key in "${!_CONFIG[@]}"; do
        section="${compound_key%%.*}"
        key="${compound_key#*.}"

        # Build var name: PROFILE_SECTION_KEY (uppercased, dashes to underscores)
        var_name="PROFILE_"
        if [[ -n "$section" ]]; then
            var_name+="${section^^}_"
        fi
        var_name+="${key^^}"
        var_name="${var_name//-/_}"

        export "$var_name"="${_CONFIG[$compound_key]}"
    done
}

# ---------------------------------------------------------------------------
# profile_get <section> <key>
# Returns the value for section.key, or empty string if not set.
# ---------------------------------------------------------------------------
profile_get() {
    local section="$1"
    local key="$2"
    printf '%s' "${_CONFIG["${section}.${key}"]:-}"
}
