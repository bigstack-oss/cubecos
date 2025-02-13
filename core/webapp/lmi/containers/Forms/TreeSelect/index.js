import React, { Component } from 'react';
import TreeSelect from '../../../components/uielements/treeSelect';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';

const SHOW_PARENT = TreeSelect.SHOW_PARENT;

const treeData = [
  {
    label: 'Node1',
    value: '0-0',
    key: '0-0',
    children: [
      {
        label: 'Child Node1',
        value: '0-0-0',
        key: '0-0-0'
      }
    ]
  },
  {
    label: 'Node2',
    value: '0-1',
    key: '0-1',
    children: [
      {
        label: 'Child Node3',
        value: '0-1-0',
        key: '0-1-0'
      },
      {
        label: 'Child Node4',
        value: '0-1-1',
        key: '0-1-1'
      },
      {
        label: 'Child Node5',
        value: '0-1-2',
        key: '0-1-2'
      }
    ]
  }
];

export default class extends Component {
  state = {
    value: ['0-0-0']
  };
  onChange = value => {
    this.setState({ value });
  };
  render() {
    const tProps = {
      treeData,
      value: this.state.value,
      onChange: this.onChange,
      multiple: true,
      treeCheckable: true,
      showCheckedStrategy: SHOW_PARENT,
      searchPlaceholder: 'Please select',
      style: {
        width: 300
      }
    };
    return (
      <LayoutWrapper>
        <PageHeader>TreeSelect</PageHeader>
        <Box title="Multiple" subtitle="Multiple and checkable.">
          <ContentHolder>
            <TreeSelect {...tProps} />
          </ContentHolder>
        </Box>
      </LayoutWrapper>
    );
  }
}
