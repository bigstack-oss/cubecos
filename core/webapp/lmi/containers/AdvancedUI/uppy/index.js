import React, { Component } from 'react';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import Uppy from '../../../components/uielements/uppy';
import config from './config';
import UppyStyleWrapper from './uppy.style';
export default class extends Component {
  constructor(props) {
    super(props);
    this.onSuccess = this.onSuccess.bind(this);
  }
  componentDidMount() {
    Uppy(config);
  }
  onSuccess(fileList) {}
  render() {
    return (
      <LayoutWrapper>
        <PageHeader>Uppy</PageHeader>
        <Box>
          <ContentHolder>
            <UppyStyleWrapper id="uppyHolder" />
          </ContentHolder>
        </Box>
      </LayoutWrapper>
    );
  }
}
