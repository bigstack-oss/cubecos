import React from 'react';
import Dropzone from '../../../components/uielements/dropzone.js';
import { notification } from '../../../components';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import DropzoneWrapper from './dropzone.style';
import DropzoneCss from 'dropzone/dist/min/dropzone.min.css';

export default function() {
  const componentConfig = {
    iconFiletypes: ['.jpg', '.png', '.gif'],
    method: true,
    showFiletypeIcon: true,
    uploadMultiple: false,
    maxFilesize: 2, // MB
    maxFiles: 2,
    dictMaxFilesExceeded: 'You can only upload upto 2 images',
    dictRemoveFile: 'Delete',
    dictCancelUploadConfirmation: 'Are you sure to cancel upload?',
    postUrl: 'no-url',
  };
  const djsConfig = { autoProcessQueue: false };
  const eventHandlers = {
    addedfile: file => notification('success', `${file.name} added`),
    success: file =>
      notification('success', `${file.name} successfully uploaded`),
    error: error => notification('error', 'Server is not set in the demo'),
  };
  return (<div>
    <style>{DropzoneCss}</style>
    <LayoutWrapper>
      <PageHeader>Dropzone</PageHeader>
      <Box>
        <ContentHolder>
          <DropzoneWrapper>
            <Dropzone
              config={componentConfig}
              eventHandlers={eventHandlers}
              djsConfig={djsConfig}
            />
          </DropzoneWrapper>
        </ContentHolder>
      </Box>
    </LayoutWrapper>
  </div>);
}
