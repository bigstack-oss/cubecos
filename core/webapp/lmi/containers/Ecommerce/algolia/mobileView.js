import React, { Component } from 'react';
import Button from '../../../components/uielements/button.js';
import EmptyComponent from '../../../components/emptyComponent.js';
import { InstantSearch } from 'react-instantsearch/dom';
import { Footer, Sidebar } from '../../../components/algolia';
import Content from './content';
import { setUrl, getInitData } from '../../../helpers/urlSync';
import { AlgoliaSearchConfig } from '../../../config';
import instantSearchCss from './instantSearch.css';
import AlgoliaSearchPageWrapper from './algolia.style';

export default class extends Component {
  state = {
    collapsed: true,
    searchState: getInitData(),
  };
  setVoice = query => {
    const searchState = {
      ...this.state.searchState,
      page: '1',
      query,
    };
    this.setState({ searchState });
    setUrl(searchState);
  };
  render() {
    const { collapsed } = this.state;
    const className = collapsed ? '' : 'sidebarOpen';
    const btnText = collapsed ? 'Filter' : 'Hide';
    const searchInfo = {
      ...AlgoliaSearchConfig,
      indexName: 'default_search',
      searchState: this.state.searchState,
      urlSync: true,
      onSearchStateChange: searchState => {
        this.setState({ searchState });
        setUrl(searchState);
      },
    };
    return (<div>
      <style>{instantSearchCss}</style>
      <AlgoliaSearchPageWrapper className={`${className} isoAlgoliaSearchPage`}>
        <Button
          className="ant-btn-primary isoAlgoliaSidebarToggle"
          onClick={() => {
            this.setState({ collapsed: !this.state.collapsed });
          }}
        >
          {btnText}
        </Button>
        {AlgoliaSearchConfig.appId ? (
          <InstantSearch {...searchInfo}>
            <div className="isoAlgoliaMainWrapper">
              <Sidebar setVoice={this.setVoice} />
              <Content {...this.props}/>
            </div>
            <Footer />
          </InstantSearch>
        ) : (
          <EmptyComponent value="Please include algolia appId" />
        )}
      </AlgoliaSearchPageWrapper>
    </div>);
  }
}
