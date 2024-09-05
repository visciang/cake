#!/usr/bin/env sh

set -e

# bootstrap
docker build --file Dockerfile --target cake.app --tag visciang/cake:latest .

# cake building cake
cp priv/cake /tmp/cake
sed -i '' "s/__PLEASE_PIN_A_CAKE_VERSION_HERE__/latest/" /tmp/cake
/tmp/cake run --progress plain all
/tmp/cake run --tag cake:latest cake
