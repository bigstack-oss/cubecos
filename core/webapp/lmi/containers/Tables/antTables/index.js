import React, { Component } from 'react';
import Tabs, { TabPane } from '../../../components/uielements/tabs';
import LayoutContentWrapper from '../../../components/utility/layoutWrapper';
import TableDemoStyle from './demo.style';
import fakeData from '../fakeData';
import { tableinfos } from './configs';
import * as TableViews from './tableViews/';

const dataList = new fakeData(10);

export default class AntTable extends Component {
  renderTable(tableInfo) {
    let Component;
    switch (tableInfo.value) {
      case 'sortView':
        Component = TableViews.SortView;
        break;
      case 'filterView':
        Component = TableViews.FilterView;
        break;
      case 'editView':
        Component = TableViews.EditView;
        break;
      case 'groupView':
        Component = TableViews.GroupView;
        break;
      case 'customizedView':
        Component = TableViews.CustomizedView;
        break;
      default:
        Component = TableViews.SimpleView;
    }
    return <Component tableInfo={tableInfo} dataList={dataList} />;
  }
  render() {
    return (
      <LayoutContentWrapper>
        <TableDemoStyle className="isoLayoutContent">
          <Tabs className="isoTableDisplayTab">
            {tableinfos.map(tableInfo => (
              <TabPane tab={tableInfo.title} key={tableInfo.value}>
                {this.renderTable(tableInfo)}
              </TabPane>
            ))}
          </Tabs>
        </TableDemoStyle>
      </LayoutContentWrapper>
    );
  }
}
export { TableViews, tableinfos, dataList };
