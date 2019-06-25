const axios = require('axios');
const fs = require('fs');
const { app } = require('electron');

module.exports = () =>
  axios.post('https://www.mos.ru/blockchain-yarmarki/installed/', 'Installation completed')
  .then(() => {
    fs.writeFileSync(`${app.getPath('userData')}/post.json`, JSON.stringify({ post: true }));
  })
  .catch(e => console.log('error in axios', e));
