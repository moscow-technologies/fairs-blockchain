const { app } = require('electron');
const { download } = require('electron-dl');
const fs = require('fs');

const configPath = require('../utils/configPath');

const downloadUrl = 'http://212.11.151.244:3000/fairs.snap';

// Fetch parity from https://vanity-service.parity.io/parity-binaries
module.exports = async (mainWindow, downloadItem) => {
  await download(mainWindow, downloadUrl, {
    filename: 'fair.snapshot',
    directory: app.getPath('userData'),
    onProgress: progress => {
      mainWindow.webContents.send('snapshot-download-progress', progress);
    }, // Notify the renderers
    onStarted: item => { downloadItem.item = item; }
  });
  fs.writeFileSync(configPath(), JSON.stringify({ snapshotDownloaded: true }));
};
