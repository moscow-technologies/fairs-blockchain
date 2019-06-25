const { app } = require('electron');

module.exports = () => `${app.getPath('userData')}/fair.snapshot`;
