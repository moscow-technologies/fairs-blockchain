const axios = require('axios');
const fs = require('fs');
const chainPath = require('../utils/chainPath');
const dappConf = require('../../dapp.json');

module.exports = () =>
  axios.get(dappConf.path, {
    headers: {
      'Content-Type': 'text/plain; charset=utf-8'
    }
  })
  .then(res => {
    fs.writeFileSync(chainPath(), JSON.stringify(res.data));
  });

