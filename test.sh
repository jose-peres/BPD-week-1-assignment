# Setup nvm and install pre-req
if ! command -v node &> /dev/null; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
  . "$HOME/.nvm/nvm.sh"
  nvm install --lts
fi
npm install

set -e  # Exit immediately if any command fails

# Spawn Bitcoind, and provide execution permission.
docker compose up -d
mkdir -p logs
docker compose logs -f > logs/docker.log 2>&1 &
cleanup() {
  exit_code=$?
  docker compose down -v
  exit $exit_code
}
trap cleanup EXIT

chmod +x ./bash/run-bash.sh
chmod +x ./python/run-python.sh
chmod +x ./javascript/run-javascript.sh
chmod +x ./rust/run-rust.sh
chmod +x ./run.sh

# Run the test scripts
/bin/bash run.sh
npm run test
