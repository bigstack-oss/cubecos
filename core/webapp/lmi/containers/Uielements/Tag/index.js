import React, { Component } from 'react';
import { Row, Col } from 'antd';
import Tags from '../../../components/uielements/tag';
import Input from '../../../components/uielements/input';
import Tooltip from '../../../components/uielements/tooltip';
import Button from '../../../components/uielements/button';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import basicStyle from '../../../config/basicStyle';
import IntlMessages from '../../../components/utility/intlMessages';
import TagWrapper from './tag.style';

const CheckableTag = Tags.CheckableTag;

const Tag = props => (
  <TagWrapper>
    <Tags {...props}>{props.children}</Tags>
  </TagWrapper>
);

const tagsFromServer = ['Movie', 'Books', 'Music'];

export default class extends Component {
  state = {
    selectedTags: [],
    tags: ['Unremovable', 'Tag 2', 'Tag 3'],
    inputVisible: false,
    inputValue: ''
  };
  log = e => {};
  handleChange = (tag, checked) => {
    const { selectedTags } = this.state;
    const nextSelectedTags = checked
      ? [...selectedTags, tag]
      : selectedTags.filter(t => t !== tag);
    this.setState({ selectedTags: nextSelectedTags });
  };
  preventDefault = e => {
    e.preventDefault();
  };
  handleClose = removedTag => {
    const tags = this.state.tags.filter(tag => tag !== removedTag);
    this.setState({ tags });
  };
  showInput = () => {
    this.setState({ inputVisible: true }, () => {
      document.getElementById('newTagsInput').focus();
    });
  };

  handleInputChange = e => {
    this.setState({ inputValue: e.target.value });
  };

  handleInputConfirm = () => {
    const state = this.state;
    const inputValue = state.inputValue;
    let tags = state.tags;
    if (inputValue && tags.indexOf(inputValue) === -1) {
      tags = [...tags, inputValue];
    }
    this.setState({
      tags,
      inputVisible: false,
      inputValue: ''
    });
  };
  render() {
    const { selectedTags, tags, inputVisible, inputValue } = this.state;
    const { rowStyle, colStyle, gutter } = basicStyle;
    return (
      <LayoutWrapper>
        <PageHeader>{<IntlMessages id="uiElements.tags.tags" />}</PageHeader>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.tags.basicExample" />}
              subtitle={
                <IntlMessages id="uiElements.tags.basicExampleSubTitle" />
              }
            >
              <ContentHolder>
                <Tag>{<IntlMessages id="uiElements.tags.tagOne" />}</Tag>
                <Tag>
                  <a href="https://isomorphic.redq.io/dashboard/op_tag">
                    {<IntlMessages id="uiElements.tags.link" />}
                  </a>
                </Tag>
                <Tag closable onClose={this.log}>
                  {<IntlMessages id="uiElements.tags.tagTwo" />}
                </Tag>
                <Tag closable onClose={this.preventDefault}>
                  {<IntlMessages id="uiElements.tags.preventDefault" />}
                </Tag>
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box title={<IntlMessages id="uiElements.tags.colorfulTag" />}>
              <ContentHolder>
                <Tag color="#f50">#f50</Tag>
                <Tag color="#2db7f5">#2db7f5</Tag>
                <Tag color="#87d068">#87d068</Tag>
                <Tag color="#108ee9">#108ee9</Tag>
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.tags.hotTags" />}
              subtitle={<IntlMessages id="uiElements.tags.hotTagsSubTitle" />}
            >
              <ContentHolder>
                <strong>{<IntlMessages id="uiElements.tags.hots" />} </strong>
                {tagsFromServer.map(tag => (
                  <CheckableTag
                    key={tag}
                    checked={selectedTags.indexOf(tag) > -1}
                    onChange={checked => this.handleChange(tag, checked)}
                  >
                    {tag}
                  </CheckableTag>
                ))}
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.tags.addRemoveDynamically" />}
              subtitle={
                <IntlMessages id="uiElements.tags.addRemoveDynamicallySubTitle" />
              }
            >
              <ContentHolder>
                {tags.map((tag, index) => {
                  const isLongTag = tag.length > 20;
                  const tagElem = (
                    <Tag
                      key={tag}
                      closable={index !== 0}
                      afterClose={() => this.handleClose(tag)}
                    >
                      {isLongTag ? `${tag.slice(0, 20)}...` : tag}
                    </Tag>
                  );
                  return isLongTag ? (
                    <Tooltip title={tag}>{tagElem}</Tooltip>
                  ) : (
                    tagElem
                  );
                })}
                {inputVisible && (
                  <Input
                    id="newTagsInput"
                    type="text"
                    size="small"
                    style={{ width: 78 }}
                    value={inputValue}
                    onChange={this.handleInputChange}
                    onBlur={this.handleInputConfirm}
                    onPressEnter={this.handleInputConfirm}
                  />
                )}
                {!inputVisible && (
                  <Button size="small" type="dashed" onClick={this.showInput}>
                    {<IntlMessages id="uiElements.tags.newTag" />}
                  </Button>
                )}
              </ContentHolder>
            </Box>
          </Col>
        </Row>
      </LayoutWrapper>
    );
  }
}
