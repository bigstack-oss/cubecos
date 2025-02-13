import React from 'react';
import Tree, { TreeNode } from '../../../components/uielements/tree';

export default function() {
  return (
    <Tree showLine defaultExpandedKeys={['0-0-0']}>
      <TreeNode title="parent 1" key="0-0">
        <TreeNode title="parent 1-0" key="0-0-0">
          <TreeNode title="leaf" key="0-0-0-0" />
          <TreeNode title="leaf" key="0-0-0-1" />
          <TreeNode title="leaf" key="0-0-0-2" />
        </TreeNode>
        <TreeNode title="parent 1-1" key="0-0-1">
          <TreeNode title="leaf" key="0-0-1-0" />
        </TreeNode>
        <TreeNode title="parent 1-2" key="0-0-2">
          <TreeNode title="leaf" key="0-0-2-0" />
          <TreeNode title="leaf" key="0-0-2-1" />
        </TreeNode>
      </TreeNode>
    </Tree>
  );
}
