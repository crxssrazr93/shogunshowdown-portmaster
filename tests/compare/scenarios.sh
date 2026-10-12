# Scenarios for run_capture.sh: sets FRAMES (PORTCAP_FRAMES) and INPUT (PORTCAP_INPUT).
scenario() {
  case "$1" in
    probe) FRAMES="TitleScreen:300,600,900,1200"; INPUT="";;
    *) return 1;;
  esac
}
