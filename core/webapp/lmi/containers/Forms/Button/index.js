import React, { Component } from 'react';
import { Row, Col, Icon } from 'antd';
import Button, { ButtonGroup } from '../../../components/uielements/button';
import { RadioGroup, RadioButton } from '../../../components/uielements/radio';
import Dropdown, {
  DropdownMenu,
  MenuItem
} from '../../../components/uielements/dropdown';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import basicStyle from '../../../config/basicStyle';
import IntlMessages from '../../../components/utility/intlMessages';
import { rtl } from '../../../config/withDirection';

function handleMenuClick(e) {}

const menu = (
  <DropdownMenu onClick={handleMenuClick}>
    <MenuItem key="1">1st item</MenuItem>
    <MenuItem key="2">2nd item</MenuItem>
    <MenuItem key="3">3rd item</MenuItem>
  </DropdownMenu>
);

export default class extends Component {
  state = {
    size: 'default',
    loading: false,
    iconLoading: false
  };

  handleSizeChange = e => {
    this.setState({ size: e.target.value });
  };

  enterLoading = () => {
    this.setState({ loading: true });
  };

  enterIconLoading = () => {
    this.setState({ iconLoading: true });
  };

  render() {
    const size = this.state.size;
    const margin = {
      margin: rtl === 'rtl' ? '0 0 8px 8px' : '0 8px 8px 0'
    };
    const { rowStyle, colStyle, gutter } = basicStyle;
    return (
      <LayoutWrapper>
        <PageHeader>{<IntlMessages id="forms.button.header" />}</PageHeader>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box title={<IntlMessages id="forms.button.simpleButton" />}>
              <ContentHolder>
                <Button type="primary" style={margin}>
                  {<IntlMessages id="forms.button.simpleButtonPrimaryText" />}
                </Button>
                <Button style={margin}>
                  {<IntlMessages id="forms.button.simpleButtonDefaultText" />}
                </Button>
                <Button type="dashed" style={margin}>
                  {<IntlMessages id="forms.button.simpleButtonDashedText" />}
                </Button>
                <Button type="danger">
                  {<IntlMessages id="forms.button.simpleButtonDangerText" />}
                </Button>
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box title={<IntlMessages id="forms.button.iconButton" />}>
              <ContentHolder>
                <Button
                  type="primary"
                  shape="circle"
                  icon="search"
                  style={margin}
                />
                <Button type="primary" icon="search" style={margin}>
                  {<IntlMessages id="forms.button.iconPrimaryButton" />}
                </Button>
                <Button shape="circle" icon="search" style={margin} />
                <Button icon="search">
                  {<IntlMessages id="forms.button.iconSimpleButton" />}
                </Button>
              </ContentHolder>

              <ContentHolder>
                <Button shape="circle" icon="search" style={margin} />
                <Button icon="search" style={margin}>
                  {<IntlMessages id="forms.button.iconCirculerButton" />}
                </Button>
                <Button
                  type="dashed"
                  shape="circle"
                  icon="search"
                  style={margin}
                />
                <Button type="dashed" icon="search">
                  {<IntlMessages id="forms.button.iconDashedButton" />}
                </Button>
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box title={<IntlMessages id="forms.button.SizedButton" />}>
              <ContentHolder>
                <RadioGroup value={size} onChange={this.handleSizeChange}>
                  <RadioButton value="large">Large</RadioButton>
                  <RadioButton value="default">Default</RadioButton>
                  <RadioButton value="small">Small</RadioButton>
                </RadioGroup>
              </ContentHolder>

              <ContentHolder>
                <Button
                  type="primary"
                  shape="circle"
                  icon="download"
                  size={size}
                  style={margin}
                />
                <Button
                  type="primary"
                  icon="download"
                  size={size}
                  style={margin}
                >
                  Download
                </Button>
                <Button type="primary" size={size}>
                  Normal
                </Button>
              </ContentHolder>

              <ContentHolder>
                <ButtonGroup size={size}>
                  <Button type="primary">
                    <Icon type="left" />Backward
                  </Button>
                  <Button type="primary">
                    Forward<Icon type="right" />
                  </Button>
                </ButtonGroup>
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box title={<IntlMessages id="forms.button.DisabledButton" />}>
              <ContentHolder>
                <Button type="primary" style={margin}>
                  Primary
                </Button>
                <Button type="primary" disabled>
                  Primary(disabled)
                </Button>
              </ContentHolder>

              <ContentHolder>
                <Button style={margin}>Default</Button>
                <Button disabled>Default(disabled)</Button>
              </ContentHolder>

              <ContentHolder>
                <Button style={margin}>Ghost</Button>
                <Button disabled>Ghost(disabled)</Button>
              </ContentHolder>

              <ContentHolder>
                <Button type="dashed" style={margin}>
                  Dashed
                </Button>
                <Button type="dashed" disabled>
                  Dashed(disabled)
                </Button>
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box title={<IntlMessages id="forms.button.LoadingButton" />}>
              <ContentHolder>
                <Button type="primary" loading style={margin}>
                  Loading
                </Button>
                <Button type="primary" size="small" loading>
                  Loading
                </Button>
              </ContentHolder>

              <ContentHolder>
                <Button
                  type="primary"
                  loading={this.state.loading}
                  onClick={this.enterLoading}
                  style={margin}
                >
                  Click me!
                </Button>
                <Button
                  type="primary"
                  icon="poweroff"
                  loading={this.state.iconLoading}
                  onClick={this.enterIconLoading}
                >
                  Click me!
                </Button>
              </ContentHolder>

              <ContentHolder>
                <Button shape="circle" loading style={margin} />
                <Button type="primary" shape="circle" loading />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box title={<IntlMessages id="forms.button.MultipleButton" />}>
              <ContentHolder>
                <Button type="primary" style={margin}>
                  primary
                </Button>
                <Button style={margin}>secondary</Button>
                <Dropdown overlay={menu}>
                  <Button>
                    more <Icon type="down" />
                  </Button>
                </Dropdown>
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box title={<IntlMessages id="forms.button.groupButton" />}>
              <ContentHolder>
                <h4>Basic</h4>
                <ButtonGroup style={margin}>
                  <Button>Cancel</Button>
                  <Button type="primary">OK</Button>
                </ButtonGroup>
                <ButtonGroup style={margin}>
                  <Button disabled>L</Button>
                  <Button disabled>M</Button>
                  <Button disabled>R</Button>
                </ButtonGroup>
                <ButtonGroup style={margin}>
                  <Button type="primary">L</Button>
                  <Button>M</Button>
                  <Button>M</Button>
                  <Button type="dashed">R</Button>
                </ButtonGroup>
              </ContentHolder>

              <ContentHolder>
                <h4>With Icon</h4>
                <ButtonGroup style={margin}>
                  <Button type="primary">
                    <Icon type="left" />Go back
                  </Button>
                  <Button type="primary">
                    Go forward<Icon type="right" />
                  </Button>
                </ButtonGroup>
                <ButtonGroup>
                  <Button type="primary" icon="cloud" />
                  <Button type="primary" icon="cloud-download" />
                </ButtonGroup>
              </ContentHolder>
            </Box>
          </Col>
        </Row>
      </LayoutWrapper>
    );
  }
}
