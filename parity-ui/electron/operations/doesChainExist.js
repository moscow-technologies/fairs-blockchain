const fs = require('fs');

const chainPath = require('../utils/chainPath');
const fetchChain = require('./fetchChain');

module.exports = async () => {
  if (!fs.existsSync(chainPath())) {
    await fetchChain();
  }
};
