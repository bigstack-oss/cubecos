// api/service/hex-cmds.js

const { exec } = require('child_process');
const { remote } = require('../../config-server/vars');
const logger = require('../../config-server/logger');

const CMD_HEX_CFG = "/usr/sbin/hex_config";
const CMD_HEX_CLI = "/usr/sbin/hex_cli";
const CMD_HEX_SDK = "/usr/sbin/hex_sdk";
const CMD_CUBE_CTL = "/usr/local/bin/cubectl";

class Command {
  constructor(cmd) {
    this.withRemote = remote ? true : false
    this.cmd = `${remote} ${cmd}`;
  }
  run(args) {
    const cmd = this.cmd;
    let escArgs = args;
    if (this.withRemote) // escaped \"'()
      escArgs = escArgs.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/'/g, '\\\'').replace(/\(/g, '\\(').replace(/\)/g, '\\)');
    return new Promise(function(resolve, reject) {
      const child = exec(
        `${cmd} ${escArgs}`,
        (error, stdout, stderr) => {
          logger.info(`command:`);
          logger.info(`${cmd} ${escArgs}`);
          if (stdout) {
            logger.info('return (stdout):');
            logger.info(stdout);
            resolve(stdout)
          }
          else if (stderr) {
            logger.info('return (stderr):');
            logger.info(stderr);
            reject(stderr)
          }
          else if (error) {
            logger.info('return (error):');
            logger.info(error);
            reject(error)
          }
          resolve('')
        }
      )
    })
  }
}

class HexConfig extends Command {
  constructor() {
    super(CMD_HEX_CFG);
  }
}

class HexCli extends Command {
  constructor() {
    super(CMD_HEX_CLI);
  }
}

class HexSdk extends Command {
  constructor() {
    super(CMD_HEX_SDK);
  }
}

class CubeCtl extends Command {
  constructor() {
    super(CMD_CUBE_CTL);
  }
}

module.exports = {
  HexConfig,
  HexCli,
  HexSdk,
  CubeCtl,
}