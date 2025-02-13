import React from 'react';
import { Cell } from 'fixed-data-table-2';
import ImageCellView from './imageCell';

const DateCell = ({rowIndex, data, col, ...props}) => (
  <Cell {...props}>
    {data.getObjectAt(rowIndex)[col].toLocaleString()}
  </Cell>
);

const ImageCell = ({rowIndex, data, col, ...props}) => (
  <ImageCellView src={data.getObjectAt(rowIndex)[col]} />
);

const LinkCell = ({rowIndex, data, col, ...props}) => (
  <Cell {...props}>
    <a>{data.getObjectAt(rowIndex)[col]}</a>
  </Cell>
);

const TextCell = ({rowIndex, data, col, ...props}) => (
  <Cell {...props}>
    {data.getObjectAt(rowIndex)[col]}
  </Cell>
);

class RemovableHeaderCell extends React.PureComponent {
  render() {
    const {data, rowIndex, columnKey, callback, children, ...props} = this.props;
    return (
      <Cell {...props}>
        {children}
        <a style={{float: 'right'}} onClick={() => callback(columnKey)}>
          {'\u274C'}
        </a>
      </Cell>
    );
  }
};
class SortHeaderCell extends React.Component {
  render() {
    const { sortTypes, sortChange, sortDir, children, ...props } = this.props;
    return (
      <Cell {...props}>
        <a onClick={sortChange}>
          {children} {sortDir ? (sortDir === sortTypes.ASC ? '↓' : '↑') : ''}
        </a>
      </Cell>
    );
  }
}
export {
  DateCell,
  ImageCell,
  LinkCell,
  TextCell,
  RemovableHeaderCell,
  SortHeaderCell,
}