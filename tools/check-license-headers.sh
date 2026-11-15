#!/bin/sh
#
# check-license-headers.sh: fails if a viewMD source file lacks the
# copyright and GPL notice (owner preference P-013).
#
# Checks every tracked Swift, JavaScript, CSS, HTML and YAML file except
# the bundled third-party highlight.js files, which keep their own (BSD)
# notices. Run from the repo root; CI runs it on every push.
#
# Copyright (C) 2026 Stephen Hicks, N5AC
#
# This file is part of viewMD.
#
# viewMD is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
#
# viewMD is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along
# with viewMD. If not, see <https://www.gnu.org/licenses/>.

status=0
for file in $(git ls-files '*.swift' '*.js' '*.css' '*.html' '*.yml' '*.sh' | grep -v '/highlight'); do
    # The notice must be in the file's opening comment (first 60 lines).
    if ! head -n 60 "$file" | grep -q 'Copyright (C) [0-9]* Stephen Hicks, N5AC' ||
       ! head -n 60 "$file" | grep -q 'GNU General Public License'; then
        echo "Missing copyright/GPL notice: $file"
        status=1
    fi
done
[ $status -eq 0 ] && echo "All source files carry the copyright and GPL notice."
exit $status
