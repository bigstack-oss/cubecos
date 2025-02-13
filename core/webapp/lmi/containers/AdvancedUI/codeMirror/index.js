import React, { Component } from 'react';
import { Row, Col } from 'antd';
import Switch from '../../../components/uielements/switch';
import Select, { SelectOption } from '../../../components/uielements/select';
import Form from '../../../components/uielements/form';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import basicStyle from '../../../config/basicStyle';
import { switchOptions, selectOptions, defaultValues } from './config';
import CodeMirror, { CodeMirrorToolbar } from './codeMirror.style';

import CodeMirrorAmbianceCSS from 'codemirror/theme/ambiance-mobile.css';
import CodeMirrorBase16CSS from 'codemirror/theme/base16-dark.css';
import CodeMirrorZenburnCSS from 'codemirror/theme/zenburn.css';
import CodeMirrorSolarizedCSS from 'codemirror/theme/solarized.css';
import CodeMirrorRubyBlueCSS from 'codemirror/theme/rubyblue.css';
import CodeMirrorParaisoCSS from 'codemirror/theme/paraiso-dark.css';
import CodeMirrorMidnightCSS from 'codemirror/theme/midnight.css';
import CodeMirrorMaterialCSS from 'codemirror/theme/material.css';
import CodeMirrorHopscotchCSS from 'codemirror/theme/hopscotch.css';
import CodeMirrorTwilightCSS from 'codemirror/theme/twilight.css';

const FormItem = Form.Item;
const Option = SelectOption;

export default class extends Component {
  constructor(props) {
    super(props);
    this.updateCode = this.updateCode.bind(this);
    this.toggleOptions = this.toggleOptions.bind(this);
    this.selctOptions = this.selctOptions.bind(this);
    this.state = {
      ...defaultValues,
      basicOptions: {
        lineNumbers: true,
        readOnly: false,
        tabSize: 4,
        mode: 'javascript',
        theme: 'zenburn'
      }
    };
  }
  updateCode(mode, value) {
    this.setState({
      [mode]: value
    });
  }
  toggleOptions() {
    const { basicOptions } = this.state;
    return switchOptions.map((option, index) => {
      const id = option.id;
      const onChange = () => {
        basicOptions[id] = !basicOptions[id];
        this.setState(basicOptions);
      };
      return (
        <FormItem label={option.title} key={option.id}>
          <Switch
            checked={option.value === basicOptions[id]}
            onChange={onChange}
          />
        </FormItem>
      );
    });
  }
  selctOptions() {
    const { basicOptions } = this.state;
    return selectOptions.map((option, index) => {
      const id = option.id;
      const handleChange = value => {
        basicOptions[id] = isNaN(value) ? value : parseInt(value, 10);
        this.setState(basicOptions);
      };
      return (
        <FormItem label={option.title} key={option.id}>
          <Select defaultValue={`${basicOptions[id]}`} onChange={handleChange}>
            {option.options.map(opt => (
              <Option value={opt} key={opt}>
                {opt}
              </Option>
            ))}
          </Select>
        </FormItem>
      );
    });
  }
  render() {
    const { rowStyle, colStyle, gutter } = basicStyle;
    return (
      <div>
        <style>{CodeMirrorAmbianceCSS}</style>
        <style>{CodeMirrorBase16CSS}</style>
        <style>{CodeMirrorZenburnCSS}</style>
        <style>{CodeMirrorSolarizedCSS}</style>
        <style>{CodeMirrorRubyBlueCSS}</style>
        <style>{CodeMirrorParaisoCSS}</style>
        <style>{CodeMirrorMidnightCSS}</style>
        <style>{CodeMirrorMaterialCSS}</style>
        <style>{CodeMirrorHopscotchCSS}</style>
        <style>{CodeMirrorTwilightCSS}</style>
        <LayoutWrapper>
          <PageHeader>Code Mirror</PageHeader>
          <Row style={rowStyle} gutter={gutter} justify="start">
            <Col md={24} sm={24} xs={24} style={colStyle}>
              <Box title="Basic Example">
                <ContentHolder>
                  <CodeMirrorToolbar className="isoOptionWrapper">
                    {this.toggleOptions()}
                    {this.selctOptions()}
                  </CodeMirrorToolbar>
                  <CodeMirror
                    value={this.state.basic}
                    onChange={value => this.updateCode('basic', value)}
                    options={this.state.basicOptions}
                  />
                </ContentHolder>
              </Box>
            </Col>
          </Row>
          <Row style={rowStyle} gutter={gutter} justify="start">
            <Col md={12} sm={12} xs={24} style={colStyle}>
              <Box title="Ruby Example">
                <ContentHolder>
                  <CodeMirror
                    value={this.state.ruby}
                    onChange={value => this.updateCode('ruby', value)}
                    options={{ lineNumbers: true, theme: 'hopscotch' }}
                  />
                </ContentHolder>
              </Box>
            </Col>
            <Col md={12} sm={12} xs={24} style={colStyle}>
              <Box title="Javascript Example">
                <ContentHolder>
                  <CodeMirror
                    value={this.state.javascript}
                    onChange={value => this.updateCode('javascript', value)}
                    options={{ lineNumbers: true, theme: 'twilight' }}
                  />
                </ContentHolder>
              </Box>
            </Col>
          </Row>
          <Row style={rowStyle} gutter={gutter} justify="start">
            <Col md={12} sm={12} xs={24} style={colStyle}>
              <Box title="Markdown Example">
                <ContentHolder>
                  <CodeMirror
                    value={this.state.markdown}
                    onChange={value => this.updateCode('markdown', value)}
                    options={{ lineNumbers: true, theme: 'rubyblue' }}
                  />
                </ContentHolder>
              </Box>
            </Col>
            <Col md={12} sm={12} xs={24} style={colStyle}>
              <Box title="XML Example">
                <ContentHolder>
                  <CodeMirror
                    value={this.state.xml}
                    onChange={value => this.updateCode('xml', value)}
                    options={{ lineNumbers: true, theme: 'paraiso-dark' }}
                  />
                </ContentHolder>
              </Box>
            </Col>
          </Row>
          <Row style={rowStyle} gutter={gutter} justify="start">
            <Col md={12} sm={12} xs={24} style={colStyle}>
              <Box title="PHP Example">
                <ContentHolder>
                  <CodeMirror
                    value={this.state.php}
                    onChange={value => this.updateCode('php', value)}
                    options={{ lineNumbers: true, theme: 'midnight' }}
                  />
                </ContentHolder>
              </Box>
            </Col>
            <Col md={12} sm={12} xs={24} style={colStyle}>
              <Box title="Python Example">
                <ContentHolder>
                  <CodeMirror
                    value={this.state.python}
                    onChange={value => this.updateCode('python', value)}
                    options={{ lineNumbers: true, theme: 'material' }}
                  />
                </ContentHolder>
              </Box>
            </Col>
          </Row>
        </LayoutWrapper>
      </div>
    );
  }
}
