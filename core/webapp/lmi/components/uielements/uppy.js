import Uppy from 'uppy/lib/core';
import Dashboard from 'uppy/lib/plugins/Dashboard';
import GoogleDrive from 'uppy/lib/plugins/GoogleDrive';
import Dropbox from 'uppy/lib/plugins/Dropbox';
import Instagram from 'uppy/lib/plugins/Instagram';
import Webcam from 'uppy/lib/plugins/Webcam';
import Tus10 from 'uppy/lib/plugins/Tus10';
import MetaData from 'uppy/lib/plugins/MetaData';

const SERVER = null;

export default function uppyInit(options, onSuccess) {
  const uppy = Uppy({
    debug: true,
    autoProceed: options.autoProceed,
    restrictions: options.restrictions || ''
  });
  uppy.use(Tus10, { endpoint: options.endpoint, resume: true });
  uppy.use(Dashboard, {
    trigger: options.trigger,
    inline: options.DashboardInline,
    target: options.target,
    note: options.restrictions || 'Images and video only, 300kb or less'
  });
  if (options.GoogleDrive) {
    uppy.use(GoogleDrive, { target: Dashboard, host: SERVER });
  }
  if (options.Dropbox) {
    uppy.use(Dropbox, { target: Dashboard, host: SERVER });
  }
  if (options.Instagram) {
    uppy.use(Instagram, { target: Dashboard, host: SERVER });
  }
  if (options.Webcam) {
    uppy.use(Webcam, { target: Dashboard });
  }
  uppy.use(MetaData, {
    fields: options.metaFields || []
  });
  uppy.on('core:success', fileList => {
    onSuccess(fileList);
  });
  uppy.run();
}
