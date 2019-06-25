// Copyright 2015-2017 Parity Technologies (UK) Ltd.
// This file is part of Parity.

// Parity is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// Parity is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with Parity.  If not, see <http://www.gnu.org/licenses/>.

const fs = require('fs');
const { spawn } = require('child_process');

const handleError = require('./handleError');

const parityPath = require('../utils/parityPath');
const chainPath = require('../utils/chainPath');
const snapshotPath = require('../utils/snapshotPath');
const configPath = require('../utils/configPath');

let parityRestore = null; // Will hold the running parity instance

// These are errors output by parity, which Parity UI ignores (i.e. doesn't panic)
// They happen when an instance of parity is already running, and parity-ui
// tries to launch another one.

module.exports = {
  restoreSnapshot (mainWindow) {
    if (parityRestore) {
      return;
    }
    console.log('start restore');
    parityRestore = spawn(parityPath(), ['restore', snapshotPath(), '--chain', chainPath()]);

    parityRestore.stdout.on('data', data => {
      console.log(data.toString());
    });

    parityRestore.stderr.on('data', data => {
      console.log(data.toString());
      const param = data.toString().split(' ');

      if (param[3] === 'Processed') {
        const numbers = param[4].split('/');
        const process = Number(numbers[0]) / Number(numbers[1]);

        if (mainWindow && mainWindow.webContents) {
          mainWindow.webContents.send('snapshot-restored', process);
        }
      }
    });

    parityRestore.on('error', err => {
      console.log(err);
      handleError(err, 'An error occured while running restore.', true);
    });

    parityRestore.on('close', (exitCode, signal) => {
      console.log(exitCode, signal);

      if (exitCode === 0) {
        const config = JSON.parse(fs.readFileSync(configPath()));

        config.restored = true;
        fs.writeFileSync(configPath(), JSON.stringify(config));
        if (mainWindow && mainWindow.webContents) {
          mainWindow.webContents.send('snapshot-restored', 'restored');
        }
        return;
      }

      if (signal !== 'SIGTERM') {
        handleError(
          new Error(`Exit code ${exitCode}, with signal ${signal}.`),
          'An error occured while stoping restore.',
          true
        );
      }
    });
  },
  killRestoreSnapshot () {
    if (parityRestore) {
      console.log('Stopping restore.');
      parityRestore.kill();
      parityRestore = null;
    }
  }
};
