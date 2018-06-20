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

parity --chain chain.json --bootnodes enode://61e3cab766ad322e659261add0221048af2e8c0147746118c5915280a54415c386d82e97652176c2ae52e1ac6e0efde309096f653dc8a92e6e96e9d545d33213@94.79.51.218:30303,enode://1538b728e5d558622dacde3997a2f3b7bac8ef8568e1180c033d5367721822b13b0e2efe3e362dbfae7938429f7648f389efcac4b0611511f603eacfe539081c@94.79.51.219:30303,enode://72c7674cb736be97795bb5d71e3f5994aa7987b442bcb0f7bcc40ef731801e03bc5bb33d6288d77a71512debb0e8a630ba25a922557e989018313b9a809f700d@94.79.51.220:30303

open -a Parity\ UI
