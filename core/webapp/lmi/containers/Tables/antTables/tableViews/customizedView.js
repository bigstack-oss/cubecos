import React, { Component } from 'react';
import TableWrapper, { CustomizedTableWrapper } from '../antTable.style';
import Switch from '../../../../components/uielements/switch';
import Form from '../../../../components/uielements/form';
const FormItem = Form.Item;

const expandedRowRender = record =>
  <p>{`${record.firstName} lives in ${record.city}`}</p>;
const title = () => 'Here is title';
const showHeader = true;
const footer = () => 'Here is footer';
const scroll = { y: 240 };

const toggleOptions = [
  {
    defaultValue: true,
    title: 'Bordered',
    key: 'bordered',
  },
  {
    defaultValue: true,
    title: 'Loading',
    key: 'loading',
  },
  {
    defaultValue: true,
    title: 'Pagination',
    key: 'pagination',
  },
  {
    defaultValue: title,
    title: 'Title',
    key: 'title',
  },
  {
    defaultValue: showHeader,
    title: 'Show Header',
    key: 'showHeader',
  },
  {
    defaultValue: footer,
    title: 'Footer',
    key: 'footer',
  },
  {
    defaultValue: expandedRowRender,
    title: 'Expanded Row Render',
    key: 'expandedRowRender',
  },
  {
    defaultValue: {},
    title: 'Checkbox',
    key: 'rowSelection',
  },
  {
    defaultValue: scroll,
    title: 'Scrollable',
    key: 'scroll',
  },
];
export default class CustomizedView extends Component {
  constructor(props) {
    super(props);
    this.renderSwitch = this.renderSwitch.bind(this);
    this.state = {
      bordered: undefined,
      loading: undefined,
      pagination: true,
      size: 'default',
      expandedRowRender,
      title,
      showHeader,
      footer,
      rowSelection: {},
      scroll: undefined,
    };
  }
  renderSwitch(option) {
    const checked = this.state[option.key] !== undefined;
    const onChange = () => {
      if (!checked) {
        this.setState({ [option.key]: option.defaultValue });
      } else {
        this.setState({ [option.key]: undefined });
      }
    };
    return (
      <FormItem label={option.title} key={option.key}>
        <Switch checked={checked} onChange={onChange} />
      </FormItem>
    );
  }
  render() {
    return (
      <CustomizedTableWrapper className="isoCustomizedTableWrapper">
        <div className="isoCustomizedTableControlBar">
          <Form layout="inline">
            {toggleOptions.map(option => this.renderSwitch(option))}
          </Form>
        </div>
        <TableWrapper
          {...this.state}
          columns={this.props.tableInfo.columns}
          dataSource={this.props.dataList.getAll()}
          className="isoCustomizedTable"
        />
      </CustomizedTableWrapper>
    );
  }
}
