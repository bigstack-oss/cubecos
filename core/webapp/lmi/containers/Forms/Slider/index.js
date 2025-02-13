import React, { Component } from 'react';
import Slider from '../../../components/uielements/slider';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';

export default class extends Component {
  onChange = value => {};
  onAfterChange = value => {};
  render() {
    return (
      <LayoutWrapper>
        <PageHeader>Slider</PageHeader>

        <Box
          title="Event"
          subtitle="The onChange callback function will fire when the user changes the slider's value. The onAfterChange callback function will fire when onmouseup fired."
        >
          <ContentHolder>
            <Slider
              defaultValue={30}
              onChange={this.onChange}
              onAfterChange={this.onAfterChange}
            />
            <Slider
              range
              step={10}
              defaultValue={[20, 50]}
              onChange={this.onChange}
              onAfterChange={this.onAfterChange}
            />
          </ContentHolder>
        </Box>
      </LayoutWrapper>
    );
  }
}
