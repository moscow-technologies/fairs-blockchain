const fs = require('fs');
const { app } = require('electron');
const postRequest = require('../utils/postRequest');

module.exports = async () => {
  if (!fs.existsSync(`${app.getPath('userData')}/post.json`)) {
    await postRequest();
  }
};
