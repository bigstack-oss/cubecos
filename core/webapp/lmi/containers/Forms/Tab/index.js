import React, { Component } from 'react';
import { Icon } from 'antd';
import Tabs, { TabPane } from '../../../components/uielements/tabs';
import Select, { SelectOption } from '../../../components/uielements/select';
import Button from '../../../components/uielements/button';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import IntlMessages from '../../../components/utility/intlMessages';

const Option = SelectOption;

function callback(key) {}

const operations = <Button>Extra Action</Button>;

export default class extends Component {
  constructor(props) {
    super(props);
    this.newTabIndex = 0;
    const panes = [
      {
        title: 'Tab 1',
        content: 'Content of Tab 1',
        key: '1',
        closable: false
      },
      { title: 'Tab 2', content: 'Content of Tab 2', key: '2' }
    ];
    this.state = {
      activeKey: panes[0].key,
      panes
    };
  }

  onChange = activeKey => {
    this.setState({ activeKey });
  };
  onEdit = (targetKey, action) => {
    this[action](targetKey);
  };
  add = () => {
    const panes = this.state.panes;
    const activeKey = `newTab${this.newTabIndex++}`;
    panes.push({
      title: 'New Tab',
      content: 'Content of new Tab',
      key: activeKey
    });
    this.setState({ panes, activeKey });
  };
  remove = targetKey => {
    let activeKey = this.state.activeKey;
    let lastIndex;
    this.state.panes.forEach((pane, i) => {
      if (pane.key === targetKey) {
        lastIndex = i - 1;
      }
    });
    const panes = this.state.panes.filter(pane => pane.key !== targetKey);
    if (lastIndex >= 0 && activeKey === targetKey) {
      activeKey = panes[lastIndex].key;
    }
    this.setState({ panes, activeKey });
  };
  state = {
    tabPosition: 'top'
  };
  changeTabPosition = tabPosition => {
    this.setState({ tabPosition });
  };
  render() {
    return (
      <LayoutWrapper>
        <PageHeader>{<IntlMessages id="forms.Tabs.header" />}</PageHeader>
        <Box title={<IntlMessages id="forms.Tabs.basicTitle" />}>
          <Tabs defaultActiveKey="1" onChange={callback}>
            <TabPane tab="Tab 1" key="1">
              Content of Tab Pane 1
            </TabPane>
            <TabPane tab="Tab 2" key="2">
              Content of Tab Pane 2
            </TabPane>
            <TabPane tab="Tab 3" key="3">
              Content of Tab Pane 3
            </TabPane>
          </Tabs>
        </Box>
        <Box
          title={<IntlMessages id="forms.Tabs.simpleTabTitle" />}
          subtitle={<IntlMessages id="forms.Tabs.simpleTabSubTitle" />}
        >
          <Tabs defaultActiveKey="1">
            <TabPane tab="Tab 1" key="1">
              Tab 1
            </TabPane>
            <TabPane tab="Tab 2" disabled key="2">
              Tab 2
            </TabPane>
            <TabPane tab="Tab 3" key="3">
              Tab 3
            </TabPane>
          </Tabs>
        </Box>
        <Box title={<IntlMessages id="forms.Tabs.iconTabTitle" />}>
          <Tabs defaultActiveKey="2">
            <TabPane
              tab={
                <span>
                  <Icon type="apple" />Tab 1
                </span>
              }
              key="1"
            >
              Tab 1
            </TabPane>
            <TabPane
              tab={
                <span>
                  <Icon type="android" />Tab 2
                </span>
              }
              key="2"
            >
              Tab 2
            </TabPane>
          </Tabs>
        </Box>
        <Box title={<IntlMessages id="forms.Tabs.miniTabTitle" />}>
          <Tabs defaultActiveKey="2" size="small">
            <TabPane tab="Tab 1" key="1">
              Content of tab 1
            </TabPane>
            <TabPane tab="Tab 2" key="2">
              Content of tab 2
            </TabPane>
            <TabPane tab="Tab 3" key="3">
              Content of tab 3
            </TabPane>
          </Tabs>
        </Box>
        <Box title={<IntlMessages id="forms.Tabs.extraTabTitle" />}>
          <Tabs tabBarExtraContent={operations}>
            <TabPane tab="Tab 1" key="1">
              Content of tab 1
            </TabPane>
            <TabPane tab="Tab 2" key="2">
              Content of tab 2
            </TabPane>
            <TabPane tab="Tab 3" key="3">
              Content of tab 3
            </TabPane>
          </Tabs>
        </Box>
        <Box
          title={<IntlMessages id="forms.Tabs.TabpositionTitle" />}
          subtitle={<IntlMessages id="forms.Tabs.TabpositionSubTitle" />}
        >
          <div style={{ marginBottom: 16 }}>
            Tab position：
            <Select
              defaultValue="top"
              value={this.state.tabPosition}
              onChange={this.changeTabPosition}
              dropdownMatchSelectWidth={false}
            >
              <Option value="top">top</Option>
              <Option value="bottom">bottom</Option>
              <Option value="left">left</Option>
              <Option value="right">right</Option>
            </Select>
          </div>
          <Tabs tabPosition={this.state.tabPosition}>
            <TabPane tab="Tab 1" key="1">
              Content of Tab 1
            </TabPane>
            <TabPane tab="Tab 2" key="2">
              Content of Tab 2
            </TabPane>
            <TabPane tab="Tab 3" key="3">
              Content of Tab 3
            </TabPane>
          </Tabs>
        </Box>
        <Box title={<IntlMessages id="forms.Tabs.cardTitle" />}>
          <Tabs onChange={callback} type="card">
            <TabPane tab="Tab 1" key="1">
              Content of Tab Pane 1
            </TabPane>
            <TabPane tab="Tab 2" key="2">
              Content of Tab Pane 2
            </TabPane>
            <TabPane tab="Tab 3" key="3">
              Content of Tab Pane 3
            </TabPane>
          </Tabs>
        </Box>
        <Box title={<IntlMessages id="forms.Tabs.editableTitle" />}>
          <Tabs
            onChange={this.onChange}
            activeKey={this.state.activeKey}
            type="editable-card"
            onEdit={this.onEdit}
          >
            {this.state.panes.map(pane => (
              <TabPane tab={pane.title} key={pane.key} closable={pane.closable}>
                {pane.content}
              </TabPane>
            ))}
          </Tabs>
        </Box>
        <Box title={<IntlMessages id="forms.Tabs.verticalTitle" />}>
          <div className="card-container">
            <Tabs
              defaultActiveKey="1"
              tabPosition="left"
              style={{ height: 220 }}
            >
              <TabPane tab="Tab 1" key="1">
                Content of tab 1
              </TabPane>
              <TabPane tab="Tab 2" key="2">
                Content of tab 2
              </TabPane>
              <TabPane tab="Tab 3" key="3">
                Content of tab 3
              </TabPane>
              <TabPane tab="Tab 4" key="4">
                Content of tab 4
              </TabPane>
              <TabPane tab="Tab 5" key="5">
                Content of tab 5
              </TabPane>
              <TabPane tab="Tab 6" key="6">
                Content of tab 6
              </TabPane>
              <TabPane tab="Tab 7" key="7">
                Content of tab 7
              </TabPane>
              <TabPane tab="Tab 8" key="8">
                Content of tab 8
              </TabPane>
              <TabPane tab="Tab 9" key="9">
                Content of tab 9
              </TabPane>
              <TabPane tab="Tab 10" key="10">
                Content of tab 10
              </TabPane>
              <TabPane tab="Tab 11" key="11">
                Content of tab 11
              </TabPane>
            </Tabs>
          </div>
        </Box>
      </LayoutWrapper>
    );
  }
}
