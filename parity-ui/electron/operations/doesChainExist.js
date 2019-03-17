const fs = require('fs');
const util = require('util');

const chainPath = require('../utils/chainPath');

const fsExists = util.promisify(fs.stat);

module.exports = () => fsExists(chainPath());
