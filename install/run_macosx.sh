#!/usr/bin/env bash

which -s brew
if [[ $? != 0 ]] ;
then
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
else
    brew update
fi

brew tap paritytech/paritytech

if brew ls --versions parity > /dev/null;
then
  brew uninstall parity
fi

brew install parity --stable

if !(brew ls --versions wget > /dev/null;)
then
  brew install wget
fi

wget https://github.com/parity-js/shell/releases/download/v0.1.4/parity-ui-0.1.4.pkg -O parity-ui-0.1.4.pkg
sudo installer -pkg parity-ui-0.1.4.pkg -target /
rm parity-ui-0.1.4.pkg

wget https://github.com/moscow-technologies/fairs-blockchain/raw/master/install/fairs-dapp.zip -O fairs-dapp.zip
unzip fairs-dapp.zip
rm fairs-dapp.zip
rm -rf $HOME/Library/Application\ Support/io.parity.ethereum/dapps/fairs-dapp
mv -f $PWD/fairs-dapp $HOME/Library/Application\ Support/io.parity.ethereum/dapps/

wget -q https://raw.githubusercontent.com/moscow-technologies/fairs-blockchain/master/config/chain.json -O chain.json

parity signer new-token

parity --chain chain.json --bootnodes enode://1412ee9b9e23700e4a67a8fe3d8d02e10376b6e1cb748eaaf8aa60d4652b27872a8e1ad65bb31046438a5d3c1b71b00ec3ce0b4b42ac71464b28026a3d0b53af@94.79.51.218:30303,enode://9e0036d4200f4a6124cf02ae0f760d04ff213d96344e02fe181bb18a2710a2b8ab85cd3e17073b77a723724b13a3e7ffd49451571464a5414a2ce44e92f50e62@94.79.51.219:30303,enode://d9139e0a0d1a3169108219bad9ae77eebedbb384b63000509a25e5f42ebac887dca73dce50abc661d2ca9bc45ebc4be84f2e7fb38938c3c51f034233f216e7e0@94.79.51.220:30303

open -a Parity\ UI
