import React from 'react';
import { createConnector } from 'react-instantsearch';
import ContentElement from './contentElement';
import EmptyComponent from '../../../components/emptyComponent.js';
import { LoaderElement } from '../../../components/algolia/algoliaComponent.style';

export default createConnector({
  displayName: 'CustomResults',
  getProvidedProps(props, searchState, searchResults) {
    const status = searchResults.results
      ? searchResults.results.nbHits === 0
      : 'loading';
    return { query: searchState.query, status };
  }
})(({ status, query, ...props }) => {
  if (status === 'loading') {
    return (
      <LoaderElement className="isoContentLoader">
        <div className="loaderElement" />
      </LoaderElement>
    );
  } else if (status) {
    return <EmptyComponent value="No results for these filtering" />;
  } else {
    return <ContentElement {...props} />;
  }
});
