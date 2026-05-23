# Snapshot file
# Unset all aliases to avoid conflicts with functions
unalias -a 2>/dev/null || true
shopt -s expand_aliases
# Check for rg availability
if ! (unalias rg 2>/dev/null; command -v rg) >/dev/null 2>&1; then
  function rg {
  local _cc_bin="${CLAUDE_CODE_EXECPATH:-}"
  [[ -x $_cc_bin ]] || _cc_bin=/c/Users/Owner/.local/bin/claude.exe
  if [[ ! -x $_cc_bin ]]; then command rg "$@"; return; fi
  if [[ -n $ZSH_VERSION ]]; then
    ARGV0=rg "$_cc_bin" "$@"
  elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
    ARGV0=rg "$_cc_bin" "$@"
  elif [[ $BASHPID != $$ ]]; then
    exec -a rg "$_cc_bin" "$@"
  else
    (exec -a rg "$_cc_bin" "$@")
  fi
}
fi
export PATH='/c/Users/Owner/bin:/mingw64/bin:/usr/local/bin:/usr/bin:/bin:/mingw64/bin:/usr/bin:/c/Users/Owner/bin:/c/WINDOWS/system32:/c/WINDOWS:/c/WINDOWS/System32/Wbem:/c/WINDOWS/System32/WindowsPowerShell/v1.0:/c/WINDOWS/System32/OpenSSH:/c/Program Files/dotnet:/cmd:/c/Users/Owner/AppData/Local/Microsoft/WindowsApps:/mingw64/bin:/usr/bin/vendor_perl:/usr/bin/core_perl:/c/Users/Owner/AppData/Roaming/Claude/local-agent-mode-sessions/skills-plugin/1eb35a1e-5c82-4057-a3e9-85a4d77d4d98/aea4a1be-e8f3-4694-a737-88a9efefb721/bin'
