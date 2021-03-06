define [
	"base"
], (App) ->

	App.controller "ProjectPageController", ($scope, $modal, $q, $window, queuedHttp, event_tracking, $timeout, localStorage) ->
		$scope.projects = window.data.projects
		$scope.tags = window.data.tags
		$scope.notifications = window.data.notifications
		$scope.allSelected = false
		$scope.selectedProjects = []
		$scope.isArchiveableProjectSelected = false
		$scope.filter = "all"
		$scope.predicate = "lastUpdated"
		$scope.nUntagged = 0
		$scope.reverse = true
		$scope.searchText = 
			value : ""

		$timeout () ->
			recalculateProjectListHeight()
		, 10

		$scope.$watch((
			() -> $scope.projects.filter((project) -> (!project.tags? or project.tags.length == 0) and !project.archived).length
		), (newVal) -> $scope.nUntagged = newVal)

		storedUIOpts = JSON.parse(localStorage("project_list"))

		recalculateProjectListHeight = () ->
			$projListCard = $(".project-list-card")
			topOffset = $projListCard.offset()?.top
			cardPadding = $projListCard.outerHeight() - $projListCard.height()
			bottomOffset = $("footer").outerHeight()
			height = $window.innerHeight - topOffset - bottomOffset - cardPadding
			$scope.projectListHeight = height

		angular.element($window).bind "resize", () ->
			recalculateProjectListHeight()
			$scope.$apply()
			
		# Allow tags to be accessed on projects as well
		projectsById = {}
		for project in $scope.projects
			projectsById[project.id] = project

		for tag in $scope.tags
			for project_id in tag.project_ids or []
				project = projectsById[project_id]
				if project?
					project.tags ||= []
					project.tags.push tag

		markTagAsSelected = (id) ->
			for tag in $scope.tags
				if tag._id == id
					tag.selected = true
				else
					tag.selected = false
		
		$scope.changePredicate = (newPredicate)->
			if $scope.predicate == newPredicate
				$scope.reverse = !$scope.reverse
			$scope.predicate = newPredicate

		$scope.getSortIconClass = (column)->
			if column == $scope.predicate and $scope.reverse
				return "fa-caret-down"
			else if column == $scope.predicate and !$scope.reverse
				return "fa-caret-up"
			else
				return ""

		$scope.searchProjects = ->
			event_tracking.send 'project-list-page-interaction', 'project-search', 'keydown'
			$scope.updateVisibleProjects()

		$scope.clearSearchText = () ->
			$scope.searchText.value = ""
			$scope.filter = "all"
			$scope.$emit "search:clear"
			$scope.updateVisibleProjects()

		$scope.setFilter = (filter) ->
			$scope.filter = filter
			$scope.updateVisibleProjects()

		$scope.updateSelectedProjects = () ->
			$scope.selectedProjects = $scope.projects.filter (project) -> project.selected
			$scope.isArchiveableProjectSelected = $scope.selectedProjects.some (project) ->
				window.user_id == project.owner._id

		$scope.getSelectedProjects = () ->
			$scope.selectedProjects

		$scope.getSelectedProjectIds = () ->
			$scope.selectedProjects.map (project) -> project.id

		$scope.getFirstSelectedProject = () ->
			$scope.selectedProjects[0]

		$scope.updateVisibleProjects = () ->
			$scope.visibleProjects = []
			selectedTag = $scope.getSelectedTag()
			for project in $scope.projects
				visible = true
				# Only show if it matches any search text
				if $scope.searchText.value? and $scope.searchText.value != ""
					if project.name.toLowerCase().indexOf($scope.searchText.value.toLowerCase()) == -1
						visible = false
				# Only show if it matches the selected tag
				if $scope.filter == "tag" and selectedTag? and project.id not in selectedTag.project_ids
					visible = false

				# Hide tagged projects if we only want to see the uncategorized ones
				if $scope.filter == "untagged" and project.tags?.length > 0
					visible = false

				# Hide projects we own if we only want to see shared projects
				if $scope.filter == "shared" and project.accessLevel == "owner"
					visible = false

				# Hide projects from V1 if we only want to see shared projects
				if $scope.filter == "shared" and project.isV1Project
					visible = false

				# Hide projects we don't own if we only want to see owned projects
				if $scope.filter == "owned" and project.accessLevel != "owner"
					visible = false

				if $scope.filter == "archived"
					# Only show archived projects
					if !project.archived
						visible = false
				else
					# Only show non-archived projects
					if project.archived
						visible = false

				if $scope.filter == "v1" and !project.isV1Project
					visible = false

				if visible
					$scope.visibleProjects.push project
				else
					# We don't want hidden selections
					project.selected = false

			localStorage("project_list", JSON.stringify({ 
				filter: $scope.filter,
				selectedTagId: selectedTag?._id
			}))
			$scope.updateSelectedProjects()

		$scope.getSelectedTag = () ->
			for tag in $scope.tags
				return tag if tag.selected
			return null

		$scope._removeProjectIdsFromTagArray = (tag, remove_project_ids) ->
			# Remove project_id from tag.project_ids
			remaining_project_ids = []
			removed_project_ids = []
			for project_id in tag.project_ids
				if project_id not in remove_project_ids
					remaining_project_ids.push project_id
				else
					removed_project_ids.push project_id
			tag.project_ids = remaining_project_ids
			return removed_project_ids

		$scope._removeProjectFromList = (project) ->
			index = $scope.projects.indexOf(project)
			if index > -1
				$scope.projects.splice(index, 1)

		$scope.removeSelectedProjectsFromTag = (tag) ->
			tag.showWhenEmpty = true

			selected_project_ids = $scope.getSelectedProjectIds()
			selected_projects = $scope.getSelectedProjects()

			removed_project_ids = $scope._removeProjectIdsFromTagArray(tag, selected_project_ids)

			# Remove tag from project.tags
			remaining_tags = []
			for project in selected_projects
				project.tags ||= []
				index = project.tags.indexOf tag
				if index > -1
					project.tags.splice(index, 1)

			for project_id in removed_project_ids
				queuedHttp({
					method: "DELETE"
					url: "/tag/#{tag._id}/project/#{project_id}"
					headers:
						"X-CSRF-Token": window.csrfToken
				})

			# If we're filtering by this tag then we need to remove
			# the projects from view
			$scope.updateVisibleProjects()

		$scope.removeProjectFromTag = (project, tag) ->
			tag.showWhenEmpty = true

			project.tags ||= []
			index = project.tags.indexOf tag

			if index > -1
				$scope._removeProjectIdsFromTagArray(tag, [ project.id ])
				project.tags.splice(index, 1)
				queuedHttp({
					method: "DELETE"
					url: "/tag/#{tag._id}/project/#{project.id}"
					headers:
						"X-CSRF-Token": window.csrfToken
				})
				$scope.updateVisibleProjects()

		$scope.addSelectedProjectsToTag = (tag) ->
			selected_projects = $scope.getSelectedProjects()
			event_tracking.send 'project-list-page-interaction', 'project action', 'addSelectedProjectsToTag'

			# Add project_ids into tag.project_ids
			added_project_ids = []
			for project_id in $scope.getSelectedProjectIds()
				unless project_id in tag.project_ids
					tag.project_ids.push project_id
					added_project_ids.push project_id

			# Add tag into each project.tags
			for project in selected_projects
				project.tags ||= []
				unless tag in project.tags
					project.tags.push tag

			for project_id in added_project_ids
				queuedHttp.post "/tag/#{tag._id}/project/#{project_id}", {
					_csrf: window.csrfToken
				}

		$scope.createTag = (name) ->
			return tag

		$scope.openNewTagModal = (e) ->
			modalInstance = $modal.open(
				templateUrl: "newTagModalTemplate"
				controller: "NewTagModalController"
			)

			modalInstance.result.then(
				(tag) ->
					$scope.tags.push tag
					$scope.addSelectedProjectsToTag(tag)
			)

		$scope.createProject = (name, template = "none") ->
			return queuedHttp
				.post("/project/new", {
					_csrf: window.csrfToken
					projectName: name
					template: template
				})
				.then((response) ->
					{ data } = response
					$scope.projects.push {
						name: name
						_id: data.project_id
						accessLevel: "owner"
						# TODO: Check access level if correct after adding it in
						# to the rest of the app
					}
					$scope.updateVisibleProjects()
				)

		$scope.openCreateProjectModal = (template = "none") ->
			event_tracking.send 'project-list-page-interaction', 'new-project', template
			modalInstance = $modal.open(
				templateUrl: "newProjectModalTemplate"
				controller: "NewProjectModalController"
				resolve:
					template: () -> template
				scope: $scope
			)

			modalInstance.result.then (project_id) ->
				window.location = "/project/#{project_id}"

		$scope.renameProject = (project, newName) ->
			return queuedHttp.post "/project/#{project.id}/rename", {
				newProjectName: newName,
				_csrf: window.csrfToken
			}
				.then () ->
					project.name = newName

		$scope.openRenameProjectModal = () ->
			project = $scope.getFirstSelectedProject()
			return if !project? or project.accessLevel != "owner"
			event_tracking.send 'project-list-page-interaction', 'project action', 'Rename'
			modalInstance = $modal.open(
				templateUrl: "renameProjectModalTemplate"
				controller: "RenameProjectModalController"
				resolve:
					project: () -> project
				scope: $scope
			)

		$scope.cloneProject = (project, cloneName) ->
			event_tracking.send 'project-list-page-interaction', 'project action', 'Clone'
			queuedHttp
				.post("/project/#{project.id}/clone", {
					_csrf: window.csrfToken
					projectName: cloneName
				})
				.then((response) ->
					{ data } = response
					$scope.projects.push {
						name: cloneName
						id: data.project_id
						accessLevel: "owner"
						owner: {
							_id: user_id
						}
						# TODO: Check access level if correct after adding it in
						# to the rest of the app
					}
					$scope.updateVisibleProjects()
				)

		$scope.openCloneProjectModal = () ->
			project = $scope.getFirstSelectedProject()
			return if !project?

			modalInstance = $modal.open(
				templateUrl: "cloneProjectModalTemplate"
				controller: "CloneProjectModalController"
				resolve:
					project: () -> project
				scope: $scope
			)

		$scope.openArchiveProjectsModal = () ->
			modalInstance = $modal.open(
				templateUrl: "deleteProjectsModalTemplate"
				controller: "DeleteProjectsModalController"
				resolve:
					projects: () -> $scope.getSelectedProjects()
			)
			event_tracking.send 'project-list-page-interaction', 'project action', 'Delete'
			modalInstance.result.then () ->
				$scope.archiveOrLeaveSelectedProjects()

		$scope.archiveOrLeaveSelectedProjects = () ->
			$scope.archiveOrLeaveProjects($scope.getSelectedProjects())

		$scope.archiveOrLeaveProjects = (projects) ->
			projectIds = projects.map (p) -> p.id
			# Remove project from any tags
			for tag in $scope.tags
				$scope._removeProjectIdsFromTagArray(tag, projectIds)

			for project in projects
				project.tags = []
				if project.accessLevel == "owner"
					project.archived = true
					queuedHttp {
						method: "DELETE"
						url: "/project/#{project.id}"
						headers:
							"X-CSRF-Token": window.csrfToken
					}
				else
					$scope._removeProjectFromList project

					queuedHttp {
						method: "POST"
						url: "/project/#{project.id}/leave"
						headers:
							"X-CSRF-Token": window.csrfToken
					}

			$scope.updateVisibleProjects()


		$scope.openDeleteProjectsModal = () ->
			modalInstance = $modal.open(
				templateUrl: "deleteProjectsModalTemplate"
				controller: "DeleteProjectsModalController"
				resolve:
					projects: () -> $scope.getSelectedProjects()
			)

			modalInstance.result.then () ->
				$scope.deleteSelectedProjects()

		$scope.deleteSelectedProjects = () ->
			selected_projects = $scope.getSelectedProjects()
			selected_project_ids = $scope.getSelectedProjectIds()

			# Remove projects from array
			for project in selected_projects
				$scope._removeProjectFromList project

			# Remove project from any tags
			for tag in $scope.tags
				$scope._removeProjectIdsFromTagArray(tag, selected_project_ids)

			for project_id in selected_project_ids
				queuedHttp {
					method: "DELETE"
					url: "/project/#{project_id}?forever=true"
					headers:
						"X-CSRF-Token": window.csrfToken
				}

			$scope.updateVisibleProjects()

		$scope.restoreSelectedProjects = () ->
			$scope.restoreProjects($scope.getSelectedProjects())

		$scope.restoreProjects = (projects) ->
			projectIds = projects.map (p) -> p.id
			for project in projects
				project.archived = false

			for projectId in projectIds
				queuedHttp {
					method: "POST"
					url: "/project/#{projectId}/restore"
					headers:
						"X-CSRF-Token": window.csrfToken
				}

			$scope.updateVisibleProjects()

		$scope.openUploadProjectModal = () ->
			modalInstance = $modal.open(
				templateUrl: "uploadProjectModalTemplate"
				controller: "UploadProjectModalController"
			)

		$scope.downloadSelectedProjects = () ->
			$scope.downloadProjectsById($scope.getSelectedProjectIds())

		$scope.downloadProjectsById = (projectIds) ->
			event_tracking.send 'project-list-page-interaction', 'project action', 'Download Zip'
			if projectIds.length > 1
				path = "/project/download/zip?project_ids=#{projectIds.join(',')}"
			else
				path = "/project/#{projectIds[0]}/download/zip"
			window.location = path

		$scope.openV1ImportModal = (project) ->
			$modal.open(
				templateUrl: 'v1ImportModalTemplate'
				controller: 'V1ImportModalController'
				size: 'lg'
				windowClass: 'v1-import-modal'
				resolve:
					project: () -> project
			)
			
		if storedUIOpts?.filter?
			if storedUIOpts.filter == "tag" and storedUIOpts.selectedTagId?
				markTagAsSelected(storedUIOpts.selectedTagId)
			$scope.setFilter(storedUIOpts.filter)
		else
			$scope.updateVisibleProjects()

	App.controller "ProjectListItemController", ($scope, $modal, queuedHttp) ->

		$scope.shouldDisableCheckbox = (project) ->
			$scope.filter == 'archived' && project.accessLevel != 'owner'

		$scope.projectLink = (project) ->
			if project.accessLevel == 'readAndWrite' and project.source == 'token'
				"/#{project.tokens.readAndWrite}"
			else if project.accessLevel == 'readOnly' and project.source == 'token'
				"/read/#{project.tokens.readOnly}"
			else
				"/project/#{project.id}"

		$scope.isLinkSharingProject = (project) ->
			return project.source == 'token'

		$scope.ownerName = () ->
			if $scope.project.accessLevel == "owner"
				return "You"
			else if $scope.project.owner?
				return [$scope.project.owner.first_name, $scope.project.owner.last_name].filter((n) -> n?).join(" ")
			else
				return "None"

		$scope.isOwner = () ->
			window.user_id == $scope.project.owner._id

		$scope.$watch "project.selected", (value) ->
			if value?
				$scope.updateSelectedProjects()

		$scope.clone = (e) ->
			e.stopPropagation()
			$scope.project.isTableActionInflight = true
			$scope.cloneProject($scope.project, "#{$scope.project.name} (Copy)")
				.then () -> $scope.project.isTableActionInflight = false
				.catch () -> $scope.project.isTableActionInflight = false

		$scope.download = (e) ->
			e.stopPropagation()
			$scope.downloadProjectsById([$scope.project.id])

		$scope.archiveOrLeave = (e) ->
			e.stopPropagation()
			$scope.archiveOrLeaveProjects([$scope.project])

		$scope.restore = (e) ->
			e.stopPropagation()
			$scope.restoreProjects([$scope.project])

		$scope.deleteProject = (e) ->
			e.stopPropagation()
			modalInstance = $modal.open(
				templateUrl: "deleteProjectsModalTemplate"
				controller: "DeleteProjectsModalController"
				resolve:
					projects: () -> [ $scope.project ]
			)

			modalInstance.result.then () ->
				$scope.project.isTableActionInflight = true
				queuedHttp({
					method: "DELETE"
					url: "/project/#{$scope.project.id}?forever=true"
					headers:
						"X-CSRF-Token": window.csrfToken
				}).then () -> 
					$scope.project.isTableActionInflight = false
					$scope._removeProjectFromList $scope.project
					for tag in $scope.tags
						$scope._removeProjectIdsFromTagArray(tag, [ $scope.project.id ])
					$scope.updateVisibleProjects()
				.catch () -> 
					$scope.project.isTableActionInflight = false
