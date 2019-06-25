const { app } = require('electron');

module.exports = () => `${app.getPath('userData')}/config.json`;
