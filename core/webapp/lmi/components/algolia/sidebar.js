import React from 'react';
import {
  RefinementList,
  StarRating,
  Toggle,
  HierarchicalMenu,
  SearchBox,
  MultiRange,
  ClearAll
} from 'react-instantsearch/dom';
import RangeSlider from './rangeSlider';
import { SidebarWrapper } from './algoliaComponent.style';

export default ({ setVoice }) => (
  <SidebarWrapper className="isoAlgoliaSidebar">
    <SearchBox translations={{ placeholder: 'Search here' }} />

    <div className="isoAlgoliaSidebarItem">
      <h3 className="isoAlgoliaSidebarTitle">Multi Range</h3>
      <MultiRange
        attributeName="price"
        items={[
          { end: 10, label: '<$10' },
          { start: 10, end: 100, label: '$10-$100' },
          { start: 100, end: 500, label: '$100-$500' },
          { start: 500, label: '>$500' }
        ]}
      />
    </div>

    <div className="isoAlgoliaSidebarItem">
      <h3 className="isoAlgoliaSidebarTitle" style={{ marginBottom: 10 }}>
        Slider
      </h3>
      <RangeSlider attributeName="price" />
    </div>

    <div className="isoAlgoliaSidebarItem">
      <h3 className="isoAlgoliaSidebarTitle">Category</h3>
      <RefinementList attributeName="categories" />
    </div>

    <div className="isoAlgoliaSidebarItem">
      <h3 className="isoAlgoliaSidebarTitle">Brand</h3>
      <RefinementList attributeName="brand" withSearchBox />
    </div>

    <div className="isoAlgoliaSidebarItem">
      <HierarchicalMenu
        attributes={[
          'hierarchicalCategories.lvl0',
          'hierarchicalCategories.lvl1',
          'hierarchicalCategories.lvl2'
        ]}
      />
    </div>
    <div className="isoAlgoliaSidebarItem">
      <h3 className="isoAlgoliaSidebarTitle">Rating</h3>
      <StarRating attributeName="rating" style={{ background: '#ff0000' }} />
    </div>
    <div className="isoAlgoliaSidebarItem isoInline">
      <h3 className="isoAlgoliaSidebarTitle">Toggle</h3>
      <Toggle attributeName="free_shipping" label="Free Shipping" />
    </div>

    <ClearAll />
  </SidebarWrapper>
);
