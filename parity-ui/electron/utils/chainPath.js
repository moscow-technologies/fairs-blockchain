const { app } = require('electron');

module.exports = () => process.env.NODE_ENV === 'production' ? `${app.getPath('userData')}/chain.json` : 'chain.json';
