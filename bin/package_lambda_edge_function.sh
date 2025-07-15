#!/bin/sh

# Get the absolute path of the directory where the script is located
DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$DIR/../functions/src/viewer_request" || exit 1
zip -r "$DIR/../functions/dist/lambda_edge_viewer_request.zip" *

