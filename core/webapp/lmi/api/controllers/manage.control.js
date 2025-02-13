// api/controllers/manage.control.js

const httpStatus = require('http-status');
const fs = require('fs-extra');
const path = require('path');
const { spawn, exec } = require('child_process');

const { CubeCtl, HexSdk, HexConfig } = require('../services/hex-cmds');
const logger = require('../../config-server/logger');

const uploadPath = "/mnt/cephfs/glance";

exports.nodeList = async (req, res, next) => {
    try {
        const info = await new CubeCtl().run('node list --json');
        return res.end(info);
    } catch (error) {
        return next(error);
    }
};

exports.nodeRemove = async (req, res, next) => {
    try {
        const info = await new HexConfig().run('sdk_run cube_node_remove ' + req.params.hostname);
        if (info) {
            const jsonOut = JSON.parse(info);
            if (jsonOut['level'] === 'fatal' || jsonOut['level'] === 'error') {
                return res.status(400).end(info);
            }
        }
        return res.status(200).end(info);
    } catch (error) {
        logger.info('error: ' + error);
        return next(error);
    }
};

exports.licenseStatus = async (req, res, next) => {
  try {
      const license = await new HexConfig().run('sdk_run -f json license_cluster_show');
      return res.json(JSON.parse(license));
  } catch (error) {
      return next(error);
  }
};

exports.images = async (req, res, next) => {
    try {
        const images = await new HexSdk().run('os_image_list');
        return res.json(JSON.parse(images));
    } catch (error) {
        return next(error);
    }
};

exports.imageAdd = async (req, res, next) => {
    req.pipe(req.busboy); // Pipe it trough busboy
    req.busboy.on('file', (fieldname, file, filename) => {
        logger.info(`Upload to '${uploadPath}/${filename}' is starting`);

        // Create a write stream of the new file
        const fstream = fs.createWriteStream(path.join(uploadPath, filename));
        // Pipe it trough
        file.pipe(fstream);

        // On finish of the upload
        fstream.on('close', () => {
            logger.info(`Upload of '${filename}' finished and starts importing to ${req.query.project} as ${req.query.name} in the background`);
            spawn('/usr/sbin/hex_sdk', ['os_image_import_with_attrs', 'scsi', uploadPath, filename, req.query.name, 'default', req.query.project, 'private' ], {
                detached: true
            });
            res.redirect('back');
        });
    });
};

exports.imageRemove = async (req, res, next) => {
    try {
        const info = await new HexSdk().run('os_image_delete ' + req.params.id);
        return res.status(200).send(info);
    } catch (error) {
        return next(error);
    }
};

exports.instances = async (req, res, next) => {
    try {
        const ins = await new HexSdk().run('os_instance_list_for_project');
        return res.json(JSON.parse(ins));
    } catch (error) {
        return next(error);
    }
};

exports.userInstances = async (req, res, next) => {
    try {
        const ins = await new HexSdk().run(`os_instance_list_for_miq_user ${req.params.username}`);
        return res.json(JSON.parse(ins));
    } catch (error) {
        return next(error);
    }
};

exports.exportInstance = async (req, res, next) => {
    logger.info(`export instance ${req.query.name} of project ${req.query.project} in the background`);
    spawn('/usr/sbin/hex_sdk', ['os_instance_export', req.query.project, req.query.name, '/mnt/cephfs/glance', 'vmdk' ], {
        detached: true
    });
    res.redirect('back');
};

exports.getExports = async (req, res, next) => {
    try {
        const exports = await new HexSdk().run('os_instance_export_list /mnt/cephfs/glance');
        return res.json(JSON.parse(exports));
    } catch (error) {
        return next(error);
    }
};

exports.exportDownload = async (req, res, next) => {
    const file = `/mnt/cephfs/glance/${req.params.filename}`;
    res.download(file); // Set disposition and send it.
};
