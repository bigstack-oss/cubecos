import React, { Component } from 'react';
import { Hits, Pagination, SortBy, Stats } from 'react-instantsearch/dom';
import Hit from './hit';
import {
  ContentWrapper,
  TopbarWrapper,
  PaginationStyleWrapper
} from '../../../components/algolia/algoliaComponent.style';

export default class extends Component {
  render() {
    const { ecommerceView, changeView } = this.props;
    return (
      <ContentWrapper className="isoAlgoliaContentWrapper">
        <TopbarWrapper className="isoAlgoliaTopBar">
          <Stats />
          <SortBy
            defaultRefinement="default_search"
            items={[
              { value: 'default_search', label: 'Default' },
              { value: 'price_asc', label: 'Lowest Price' },
              { value: 'price_desc', label: 'Highest Price' }
            ]}
          />
          <div className="isoViewChanger">
            <button
              type="button"
              className={
                ecommerceView === 'gridView' ? (
                  'isoGridView active'
                ) : (
                  'isoGridView'
                )
              }
              onClick={() => changeView('gridView')}
            >
              <i className="ion-grid" />
            </button>
            <button
              type="button"
              className={
                ecommerceView === 'gridView' ? (
                  'isoListView'
                ) : (
                  'isoListView active'
                )
              }
              onClick={() => changeView('listView')}
            >
              <i className="ion-navicon-round" />
            </button>
          </div>
        </TopbarWrapper>
        <Hits hitComponent={Hit} {...this.props} />

        <PaginationStyleWrapper className="isoAlgoliaPagination">
          <Pagination showLast />
        </PaginationStyleWrapper>
      </ContentWrapper>
    );
  }
}
