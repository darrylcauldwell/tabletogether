#!/usr/bin/env bash
# Records the current Core Data model as the deployed CloudKit schema.
#
# Run this ONLY AFTER you have deployed the schema change to CloudKit
# Production (CloudKit Dashboard -> Deploy Schema Changes -> Development to
# Production). preflight compares the current model against this recorded hash
# and FAILS if they differ, so a committed-but-undeployed schema change can't
# silently ship and break sync (see the CloudKit sync investigation memo).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
MODEL="TableTogether/Sources/CoreData/TableTogether.xcdatamodeld/TableTogether.xcdatamodel/contents"
HASH=$(git hash-object "$MODEL")
echo "$HASH" > scripts/.deployed-schema-hash
echo "Recorded deployed CloudKit schema hash: $HASH"
echo "Commit scripts/.deployed-schema-hash to mark the deploy."
