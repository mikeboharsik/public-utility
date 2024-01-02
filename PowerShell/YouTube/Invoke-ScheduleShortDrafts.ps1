[CmdletBinding(SupportsShouldProcess = $true)]
Param(
	[Parameter(Mandatory = $false)]
	[ValidateRange(1, 24)]
	[int] $VideosPerDay = 4,

	[switch] $UseExistingData,

	[switch] $SkipDescription,

	[switch] $OnlyUpdateCache,
	
	[switch] $Commit
)

$combinedCachePath = "$PSScriptRoot\combinedCache.json"

. '.\YouTube.ps1'

Get-Random -SetSeed 140811 | Out-Null

function Get-ShuffledIndices([int] $Count) {
	[int[]] $result = @()

	do {
		$cur = $null

		do {
			[int] $cur = Get-Random -Minimum 0 -Maximum ($Count)
		} while ($result.Contains($cur))

		$result += $cur
	} while ($result.Length -lt $Count)

	return $result
}


function Get-ZeroedDate {
	[CmdletBinding()]
	Param([Nullable[DateTime]] $DateTime)

	if ($DateTime) {
		$d = $DateTime
	} else {
		$d = Get-Date
	}

	return $d.AddMinutes(-$d.Minute).AddSeconds(-$d.Second).AddMilliseconds(-$d.Millisecond)
}

if (!(Test-Path $combinedCachePath) -or $OnlyUpdateCache) {
	if (!$UseExistingData -or !$YouTubeSearchResults) {
		$YouTubeSearchResults = Get-VideosSearch

		Write-Verbose "Updated `$videos"
	}

	$YouTubeCombinedResults = [hashtable[]]@()
	$YouTubeSearchResults
		| ForEach-Object {
			$YouTubeCombinedResults += ($_ | ConvertTo-Json -Depth 10 -Compress | ConvertFrom-Json -AsHashtable)
		}

	if (!$UseExistingData -or !$YouTubeVideoResults) {
		$YouTubeVideoResults = Get-Videos -VideoIds ($YouTubeSearchResults | Select-Object -ExpandProperty id | Select-Object -ExpandProperty videoId)
	}

	$YouTubeVideoResults
		| ForEach-Object {
			$curVid = $_
			$result = $YouTubeCombinedResults | Where-Object { $curVid.id -eq $_.id.videoId }

			$result.status = $curVid.status
			$result.fileDetails = $curVid.fileDetails
		}

	Set-Content $combinedCachePath (ConvertTo-Json -Depth 10 $YouTubeCombinedResults)
}

$YouTubeCombinedResults = Get-Content $combinedCachePath | ConvertFrom-Json -Depth 10 -AsHashtable

if ($OnlyUpdateCache) {
	return
}

# we can assume that the last published video is the first video returned that has a set description
$lastVideoWithDescription = $YouTubeCombinedResults[0]

foreach ($result in $YouTubeCombinedResults) {
	if ($result.status.publishAt -gt $lastVideoWithDescription.status.publishAt) {
		$lastVideoWithDescription = $result
	}
}

if (!$lastVideoWithDescription) {
	Write-Host "No videos to schedule"

	return
}

$lastPublishedAt = $lastVideoWithDescription.snippet.publishedAt
$lastScheduledPublish = Get-ZeroedDate $lastVideoWithDescription.status.publishAt

Write-Verbose "`$lastPublishedAt (uploaded) = $lastPublishedAt"
Write-Verbose "`$lastScheduledPublish = $lastScheduledPublish"

[hashtable[]] $privateVideosWithoutSchedule = $YouTubeCombinedResults
	| Where-Object { $_.snippet.title -Match '^\d{4} \d{2} \d{2}' -and $null -eq $_.status.publishAt -and $_.snippet.publishedAt -gt $lastPublishedAt -and 'private' -eq $_.status.privacyStatus }
	| Sort-Object { $_.snippet.publishedAt }

Write-Verbose "Number of private videos without schedule: $($privateVideosWithoutSchedule.Length)"

if ($privateVideosWithoutSchedule.Length -eq 0) {
	Write-Host "No videos to schedule"

	return
}

$scheduleIntervalHours = 24 / $VideosPerDay
if ($scheduleIntervalHours % 1 -ne 0) {
	throw "Please provide a value for VideosPerDay that divides 24 evenly"
}

$metadata = @()

$randomlyOrderedIndices = Get-ShuffledIndices -Count $privateVideosWithoutSchedule.Length
foreach ($index in $randomlyOrderedIndices) {
	try {
		$video = $privateVideosWithoutSchedule[$index]

		# Write-Verbose "`$video = $(ConvertTo-Json -Depth 10 -Compress $video)"

		$lastScheduledPublish = $lastScheduledPublish.AddHours($scheduleIntervalHours)

		$curData = @{
			Id = $video.id.videoId
			Title = $video.snippet.title.Substring(11)
			Description = ''
			PublishAt = $lastScheduledPublish.ToString("yyyy-MM-ddTHH:mm:ssZ")
		}

		if ($Commit) {
			Update-Video @curData
		} else {
			Write-Verbose "Skipping commit for video [$($video.id.videoId)]"
		}

		$metadata += $curData
	} catch {
		Write-Error "Failed on video $(ConvertTo-Json -Depth 10 $video)"
	}
}

Write-Host (ConvertTo-Json -Depth 10 $metadata)
