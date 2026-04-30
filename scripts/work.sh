#!/bin/bash
set -euo pipefail

open -n "/System/Applications/Reminders.app"
open -n "/Applications/Slack.app"
open -na "/Applications/Google Chrome.app" --args --new-window "https://league.okta.com"
open -na "/Applications/Google Chrome.app" --args --new-window "https://calendar.google.com/calendar/u/0/r?pli=1"
