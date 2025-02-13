import React from 'react';
import Tree, { TreeNode } from '../../../components/uielements/tree';

export default function() {
  return (
    <Tree
      checkable
      defaultExpandedKeys={['0-0-0', '0-0-1']}
      defaultSelectedKeys={['0-0-0', '0-0-1']}
      defaultCheckedKeys={['0-0-0', '0-0-1']}
    >
      <TreeNode title="parent 1" key="0-0">
        <TreeNode title="parent 1-0" key="0-0-0" disabled>
          <TreeNode title="leaf" key="0-0-0-0" disableCheckbox />
          <TreeNode title="leaf" key="0-0-0-1" />
        </TreeNode>
        <TreeNode title="parent 1-1" key="0-0-1">
          <TreeNode
            title={<span style={{ color: '#08c' }}>sss</span>}
            key="0-0-1-0"
          />
        </TreeNode>
      </TreeNode>
    </Tree>
  );
}
