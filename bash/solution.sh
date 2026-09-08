# RPC settings
RPC_USER="alice"
RPC_PASSWORD="password"
RPC_HOST="127.0.0.1:18443"

# Helper function to make RPC calls
rpc_call() {
  local method=$1
  local params=$2
  local wallet=${3:-}

  local url="http://$RPC_HOST/"
  [ -n "$wallet" ] && url="http://$RPC_HOST/wallet/$wallet"

  curl -s --user $RPC_USER:$RPC_PASSWORD --data-binary \
    "{\"jsonrpc\": \"1.0\", \"id\":\"curltest\", \"method\": \"$method\", \"params\": $params }" \
    -H 'content-type: text/plain;' $url
}

# Helper function to load wallet
# Checks if wallets is already loaded first
create_or_load_wallet() {
  local wallet_name="$1"

  if rpc_call "listwallets" '[]' | jq -e --arg name "$wallet_name" '.result | any(. == $name)' > /dev/null; then # it's loaded
    return
  fi

  if rpc_call "listwalletdir" '[]' | jq -e --arg name "$wallet_name" '.result.wallets[].name | select(. == $name)' >/dev/null; then # exists
    rpc_call "loadwallet" "[\"$wallet_name\"]" > /dev/null
  else # does not exist
    # this already loads
    rpc_call "createwallet" "{\"wallet_name\": \"$wallet_name\"}" > /dev/null
  fi
}

# Check Connection

  # This loop helps the test script wait for docker's Core to start running
  for _ in $(seq 1 30); do
    info=$(rpc_call "getblockchaininfo" "[]")
    echo "$info" | jq -e '.error == null and .result' &> /dev/null && break
    sleep 1
  done
  echo "$info" | jq; echo

# Create and load wallet

  create_or_load_wallet "testwallet"

# Generate a new address

  address=$(rpc_call "getnewaddress" "[]" \
    "testwallet" | jq -r '.result'
  )
  #echo -e "address: $address\n" # for debugging

# Mine 103 blocks to the new address

  rpc_call "generatetoaddress" \
    "[103, \"$address\"]" \
    > /dev/null

# Send the transaction

  # Gather 3 mature 50-btc inputs. This is important for Core
  # not to fund the transaction only with 2 50-btc inputs
  # and send as 0-fee instead of 21 sats/vByte.
  # minconf=100 excludes immature coinbases (100-block maturity).
  inputs=$(rpc_call "listunspent" '[100]' "testwallet" | jq -c '
    .result
    | map(select(.spendable and .amount == 50))
    | .[:3]
    | map({txid, vout})
  ')
  #echo -n "inputs: "; echo "$inputs" | jq; echo # for debugging

  provided_address="bcrt1qq2yshcmzdlznnpxx258xswqlmqcxjs4dssfxt2"
  #echo -e "provided_address: $provided_address\n" # for debugging

  # I originally wrote this to use xxd, but then I realized
  # having that dependency is dangerous, so I think it's
  # better to just default to a hard-coded value;
  # afterall, I don't know the environment where this
  # will be tested
  if command -v xxd &>/dev/null; then
    message_hex=$(echo -n 'We are all Satoshi!!' | xxd -p)
  else
    message_hex="57652061726520616c6c205361746f7368692121"
  fi
  #echo -e "message_hex: $message_hex\n" # for debugging

  # Create array of outputs with the 100-btc and
  # the OP_RETURN one;
  # `fundrawtransaction` will include the change
  outputs=$(jq -n -c \
    --arg address "$provided_address" \
    --arg message "$message_hex" \
    '[
      {($address):100},
      {"data":($message)}
    ]'
  )
  #echo -n "outputs: "; echo "$outputs" | jq; echo # for debugging

  raw_tx=$(rpc_call "createrawtransaction" \
    "{
      \"inputs\": $inputs,
      \"outputs\": $outputs
    }" \
  )
  #echo -n "raw_tx: "; echo "$raw_tx" | jq; echo # for debugging

  # this just extracts the right field from returned object
  raw_tx_hex=$(echo "$raw_tx" | jq -r '.result')
  #echo -e "raw_tx_hex: $raw_tx_hex\n"; # for debugging

  #echo -n "Decoded tx hex: "; rpc_call "decoderawtransaction" "[\"$raw_tx_hex\"]" | jq; echo # for debugging

  # This makes Core calculate the fees
  # and add change output;
  # Seems better than doing it "by hand"
  funded=$(rpc_call "fundrawtransaction" "{
    \"hexstring\": \"$raw_tx_hex\",
    \"options\": {\"fee_rate\": 21, \"add_inputs\": false}
  }" "testwallet")
  #echo -n "funded: "; echo "$funded" | jq; echo # for debugging

  # this just extracts the right field from returned object
  funded_hex=$(echo "$funded" | jq -r '.result.hex')
  #echo -e "funded_hex: $funded_hex\n"; # for debugging

  #echo -n "Decoded funded hex: "; rpc_call "decoderawtransaction" "[\"$funded_hex\"]" | jq; echo # for debugging

  signed=$(rpc_call \
    "signrawtransactionwithwallet" \
    "[\"$funded_hex\"]" \
    "testwallet")
  #echo -n "signed: "; echo "$signed" | jq; echo # for debugging

  # this just extracts the right field from returned object
  signed_hex=$(echo "$signed" | jq -r '.result.hex')
  #echo -e "signed_hex: $signed_hex\n" # for debugging

  tx=$(rpc_call "sendrawtransaction" \
    "[\"$signed_hex\"]")
  #echo -n "tx: "; echo "$tx" | jq; echo # for debugging

  # this just extracts the right field from returned object
  txid=$(echo "$tx" | jq -r '.result')
  #echo -e "txid: $txid\n" # for debugging

# Output the transaction ID to a file

  echo "$txid" > out.txt
